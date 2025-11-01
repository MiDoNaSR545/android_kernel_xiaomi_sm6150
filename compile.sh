#!/bin/bash
#
# Compile script for kernel
#

# Exit immediately if a command exits with a non-zero status.
set -e

# Start builtin bash timer
SECONDS=0

# --- Helper Functions ---

check_variables() {
if [ "$KSU_BASE" ]; then
  # This block runs if $KSU_BASE is set and NOT empty
  echo "KSU_BASE is set to: $KSU_BASE"
else
  # This block runs if $KSU_BASE is unset OR empty (e.g., KSU_BASE="")
  echo "KSU_BASE is not set."
fi
}

setup_environment() {
  echo "Setting up build environment..."
  export ARCH=arm64
  export KBUILD_BUILD_USER=vbajs
  export KBUILD_BUILD_HOST=tbyool

  export GCC64_DIR=$PWD/gcc64
  export GCC32_DIR=$PWD/gcc32
}

setup_toolchain() {
  echo "Setting up toolchains..."

  # Setup Clang
  if [ ! -d "$PWD/clang" ]; then
    echo "Cloning Clang..."
    git clone https://gitlab.com/crdroidandroid/android_prebuilts_clang_host_linux-x86_clang-r547379.git --depth=1 -b 15.0 clang
  else
    echo "Local clang dir found, using it."
  fi

  # Setup GCC
  if [ ! -d "$PWD/gcc32" ] && [ ! -d "$PWD/gcc64" ]; then
    echo "Downloading GCC..."
    ASSET_URLS=$(curl -s "https://api.github.com/repos/mvaisakh/gcc-build/releases/latest" | grep "browser_download_url" | cut -d '"' -f 4 | grep -E "eva-gcc-arm.*\.xz")
    for url in $ASSET_URLS; do
      wget --content-disposition -L "$url"
    done
    
    for file in eva-gcc-arm*.xz; do
      # The files are actually just plain tarballs named as .xz
      if [[ "$file" == *arm64* ]]; then
        tar -xf "$file" && mv gcc-arm64 gcc64
      else
        tar -xf "$file" && mv gcc-arm gcc32
      fi
      rm -rf "$file"
    done
  else
    echo "Local gcc dirs found, using them."
  fi
}

update_path() {
  echo "Updating PATH..."
  export PATH="$PWD/clang/bin/:$GCC64_DIR/bin/:$GCC32_DIR/bin/:/usr/bin:$PATH"
}

compile_kernel() {
  echo -e "\nStarting compilation..."
  
  # 1. Make the base defconfig
  make O=out ARCH=arm64 sweet_defconfig
  if [ "$KSU_BASE" ]; then
  make O=out ARCH=arm64 vendor/$KSU_BASE.config
  fi

  # 3. Run the main build
  make -j$(nproc --all) \
    O=out \
    ARCH=arm64 \
    LLVM=1 \
    LLVM_IAS=1 \
    CROSS_COMPILE=$GCC64_DIR/bin/aarch64-elf- \
    CROSS_COMPILE_COMPAT=$GCC32_DIR/bin/arm-eabi-
}

package_output() {
  echo -e "\nPackaging outputs..."
  
  local kernel="out/arch/arm64/boot/Image"
  local dtbo="out/arch/arm64/boot/dtbo.img"
  local dtb="out/arch/arm64/boot/dtb.img"

  if [ ! -f "$kernel" ] || [ ! -f "$dtbo" ] || [ ! -f "$dtb" ]; then
    echo -e "\nCompilation failed! Output files not found."
    exit 1
  fi

  # Copy outputs to current directory with KSU_BASE prefix if exists
  if [ "$KSU_BASE" ]; then
  cp "$kernel" "./$KSU_BASE-Image"
  else
  cp "$kernel" "./Image"
  fi
  cp "$dtbo" "./dtbo.img"
  cp "$dtb" "./dtb.img"

  echo "Outputs copied to root directory with prefix '$KSU_BASE'"
}

print_summary() {
  echo -e "\nCompleted in $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s) !"
}

# --- Main Execution ---

main() {
  check_variables
  setup_environment
  setup_toolchain
  update_path
  compile_kernel
  package_output
  print_summary
}

# Run the main function
main
