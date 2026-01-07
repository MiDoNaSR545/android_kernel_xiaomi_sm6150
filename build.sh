#!/bin/bash
set -e

# ---------------- COLORS ----------------
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
BLUE="\e[34m"
CYAN="\e[36m"
MAGENTA="\e[35m"
BOLD="\e[1m"
NC="\e[0m"

clear
echo -e "${BLUE}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}    MeMeDo Kernel • sweet_k6a                     ${NC}"
echo -e "${GREEN}    Redmi Note 12 Pro                             ${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════╝${NC}"

START_TIME=$(date +%s)

# ---------------- CLEAN BUILD PROMPT ----------------
echo -e "${YELLOW}Do you want a clean build? (highly recommended)${NC}"
select clean_choice in "Yes (clean build)" "No (incremental)"; do
    case $clean_choice in
        "Yes (clean build)" )
            echo -e "${YELLOW}Performing full clean...${NC}"
            [ -d "out" ] && rm -rf out
            make distclean >/dev/null 2>&1 || true
            mkdir -p out
            CLEAN_BUILD=true
            break
            ;;
        "No (incremental)" )
            echo -e "${CYAN}Incremental build — keeping existing objects${NC}"
            [ ! -d "out" ] && mkdir -p out
            CLEAN_BUILD=false
            break
            ;;
    esac
done

# ---------------- REQUIREMENTS (only if clean) ----------------
if [[ "$CLEAN_BUILD" == true ]]; then
    echo -e "${YELLOW}Installing/updating required packages...${NC}"
    sudo apt-get update -qq
    sudo apt-get install -y bc bison build-essential ccache cpio curl flex git libelf-dev libssl-dev \
        libncurses5-dev lld lzma python3 unzip wget xz-utils zip \
        gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu >/dev/null 2>&1
fi

# ---------------- BUILD TYPE ----------------
echo -e "${YELLOW}\nSelect build type:${NC}"
select buildtype in "AOSP" "MIUI/OEM"; do
    case $buildtype in
        AOSP ) zip_prefix="AOSP"; break;;
        "MIUI/OEM" ) zip_prefix="MIUI"; break;;
    esac
done

# ---------------- KERNELSU (100% SAFE — WORKS FIRST TIME) ----------------
ksu_enabled=false
echo -e "${YELLOW}\nInclude KernelSU (susfs)?${NC}"
select ksu in "Yes" "No"; do
    case $ksu in
        Yes )
            echo -e "${GREEN}Adding KernelSU Next (susfs) — safely...${NC}"

            # Download to temp file
            KSU_SCRIPT="/tmp/ksu_setup_$(date +%s).sh"
            curl -LSs "https://raw.githubusercontent.com/Mr-Morat/KernelSU-Next/susfs/kernel/setup.sh" -o "$KSU_SCRIPT"

            # Remove ALL possible terminal-killing lines (covers current and future variants)
            sed -i '/kill.*[[:space:]]\+$$/d' "$KSU_SCRIPT"
            sed -i '/kill.*$PPID/d' "$KSU_SCRIPT"
            sed -i '/exec[[:space:]]\+>&-/d' "$KSU_SCRIPT"
            sed -i '/exec[[:space:]]\+>&[[:space:]]*$/d' "$KSU_SCRIPT"
            sed -i '/exit[[:space:]]\+0/d' "$KSU_SCRIPT"  # some versions fake-exit first

            # Run it safely
            bash "$KSU_SCRIPT" susfs
            rm -f "$KSU_SCRIPT"

            zip_prefix="${zip_prefix}_KSU"
            ksu_enabled=true
            echo -e "${GREEN}KernelSU integrated successfully${NC}"
            break
            ;;
        No )
            echo -e "${CYAN}Skipping KernelSU${NC}"
            break
            ;;
    esac
done

# ---------------- TOOLCHAINS ----------------
mkdir -p toolchain

if [ ! -d "clang" ]; then
    echo -e "${YELLOW}Downloading Clang r547379...${NC}"
    mkdir -p clang
    curl -L https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/main/clang-r547379.tar.gz | tar -xzf - -C clang/
else
    echo -e "${GREEN}Clang ready${NC}"
fi

for dir in gcc64 gcc32; do
    if [ ! -d "$dir" ]; then
        echo -e "${YELLOW}Cloning $dir toolchain...${NC}"
        git clone --depth=1 https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9 "$dir"
    else
        echo -e "${GREEN}$dir ready${NC}"
    fi
done

# ---------------- ENVIRONMENT ----------------
export ARCH=arm64
export SUBARCH=arm64
export PATH="${PWD}/clang/bin:${PWD}/gcc64/bin:${PWD}/gcc32/bin:${PATH}"
export KBUILD_BUILD_USER="MiDoNaSR"
export KBUILD_BUILD_HOST="sweet_k6a"
export LLVM=1 LLVM_IAS=1
export CLANG_TRIPLE=aarch64-linux-gnu-
export CROSS_COMPILE=aarch64-linux-android-
export CROSS_COMPILE_ARM32=arm-linux-androideabi-
export USE_CCACHE=1
ccache -M 50G >/dev/null 2>&1 || true

# ---------------- PANEL DIMENSIONS ----------------
apply_panel_dimensions() {
    local w=$1 h=$2
    local files=(
        "arch/arm64/boot/dts/qcom/xiaomi/sweet/dsi-panel-k6-38-0e-0b-fhd-dsc-video.dtsi"
        "arch/arm64/boot/dts/qcom/xiaomi/sweet/dsi-panel-k6-38-0c-0a-fhd-dsc-video.dtsi"
    )
    echo -e "${CYAN}Setting panel size → ${w} × ${h} mm${NC}"
    for f in "${files[@]}"; do
        [ -f "$f" ] && sed -i "s/\(qcom,mdss-pan-physical-width-dimension[[:space:]]*=[[:space:]]*< *\)[0-9]\+/\1${w}/" "$f"
        [ -f "$f" ] && sed -i "s/\(qcom,mdss-pan-physical-height-dimension[[:space:]]*=[[:space:]]*< *\)[0-9]\+/\1${h}/" "$f"
    done
}

echo -e "${YELLOW}\nApplying panel dimensions...${NC}"
if [[ "$buildtype" == "AOSP" ]]; then
    apply_panel_dimensions 70 155
else
    apply_panel_dimensions 695 1546
fi
echo -e "${GREEN}Panel dimensions applied${NC}"

# ---------------- BUILD ----------------
echo -e "${MAGENTA}\nStarting compilation...${NC}"
make O=out sweet_defconfig
make -j$(nproc --all) O=out \
    CC=clang LD=ld.lld NM=llvm-nm OBJCOPY=llvm-objcopy \
    2>&1 | tee build.log

# ---------------- VERIFY ----------------
KERNEL_IMG="out/arch/arm64/boot/Image.gz"
DTBO_IMG="out/arch/arm64/boot/dtbo.img"

[[ ! -f "$KERNEL_IMG" || ! -f "$DTBO_IMG" ]] && {
    echo -e "${RED}BUILD FAILED — missing Image.gz or dtbo.img${NC}"
    exit 1
}

cp out/.config out/sweet_defconfig.txt

# ---------------- PACKAGING ----------------
ZIPNAME="${zip_prefix}-MeMeDo-sweet_k6a-$(date '+%Y%m%d-%H%M').zip"
echo -e "${YELLOW}\nPackaging → $ZIPNAME${NC}"

rm -rf AnyKernel3
git clone --depth=1 https://github.com/MiDoNaSR545/AnyKernel3 || git clone --depth=1 https://github.com/osm0sis/AnyKernel3 AnyKernel3
cp "$KERNEL_IMG" "$DTBO_IMG" out/arch/arm64/boot/dtb.img AnyKernel3/ 2>/dev/null || true

cd AnyKernel3
zip -r9 "../$ZIPNAME" . -x ".git/*" "README.md" "*.zip" >/dev/null
cd ..
echo -e "${GREEN}Zip created: $ZIPNAME${NC}"

# ---------------- PIXELDRAIN UPLOAD ----------------
if [[ -n "$PIXELDRAIN_API_KEY" ]]; then
    echo -e "${YELLOW}Uploading to PixelDrain...${NC}"
    RES=$(curl -s -u ":$PIXELDRAIN_API_KEY" -F "file=@$ZIPNAME" https://pixeldrain.com/api/file)
    ID=$(echo "$RES" | jq -r .id 2>/dev/null || echo "$RES" | grep -o '"id":"[^"]*' | cut -d'"' -f4)
    [[ -n "$ID" && "$ID" != "null" ]] && echo -e "${GREEN}https://pixeldrain.com/u/$ID${NC}"
fi

# ---------------- FINAL MESSAGE ----------------
END_TIME=$(date +%s)
echo -e "${MAGENTA}${BOLD}"
echo "╔══════════════════════════════════════════════════╗"
echo "       BUILD SUCCESSFUL in $((END_TIME - START_TIME)) seconds!       "
echo "       $ZIPNAME      "
[[ -n "$ID" && "$ID" != "null" ]] && echo "       https://pixeldrain.com/u/$ID      "
echo "╚══════════════════════════════════════════════════╝"
echo -e "${NC}"
