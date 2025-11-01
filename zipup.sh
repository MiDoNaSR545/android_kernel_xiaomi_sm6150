#!/bin/bash
#
# Zipup script for kernel
#

# Exit immediately if a command exits with a non-zero status.
set -e

7z a -t7z -mx=9 "Image.7z" ./*-Image ./Image
if ! git clone https://github.com/tbyool/AnyKernel3.git -b master AnyKernel3; then
	echo -e "\nCouldn't clone AnyKernel3! Aborting..."
	exit 1
fi
cp ./Image.7z AnyKernel3
cp ./dtbo.img AnyKernel3
cp ./dtb.img AnyKernel3
cd AnyKernel3
zip -r9 "../$ZIPNAME" * -x .git README.md
cd ..
rm -rf AnyKernel3
