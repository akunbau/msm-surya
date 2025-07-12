#!/bin/bash
set -eu
#
# Modified Compile script for KernullException kernel
# Based on StormBreaker script by Adithya R.
# Modified by Gemini for dual build (KSU-default & Vanilla)
# Modified to use custom clang and AnyKernel3
#

SECONDS=0 # builtin bash timer
TC_DIR="$(pwd)/clang-llvm"
AK3_REPO="https://github.com/ekqiplur/AnyKernel3.git"
DEFCONFIG="surya_defconfig"
DEFCONFIG_PATH="arch/arm64/configs/$DEFCONFIG"
DEFCONFIG_BACKUP_PATH="${DEFCONFIG_PATH}.bak"

# --- Cleanup Function ---
# Ensures the original defconfig is restored on exit or interruption
cleanup() {
  if [ -f "${DEFCONFIG_BACKUP_PATH}" ]; then
    echo -e "\nRestoring original defconfig..."
    mv "${DEFCONFIG_BACKUP_PATH}" "${DEFCONFIG_PATH}"
  fi
  # Clean up any leftover AnyKernel3 directory
  rm -rf AnyKernel3
}
trap cleanup EXIT INT TERM

# Function to perform a build
# $1: Build Type (e.g., Vanilla, KSU)
# $2: Output Directory (e.g., out_vanilla)
# $3: Zip Name
do_build() {
    local BUILD_TYPE=$1
    local OUT_DIR=$2
    local ZIPNAME=$3
    local START_TIME=$SECONDS

    echo "================================================="
    echo "Starting Build: ${BUILD_TYPE}"
    echo "================================================="

    # Setup output dir
    make O=${OUT_DIR} ARCH=arm64 ${DEFCONFIG}

    echo -e "\nStarting compilation for ${BUILD_TYPE}...\n"
    make -j$(nproc --all) O=${OUT_DIR} ARCH=arm64 CC=clang LD=ld.lld AS=llvm-as AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabi- LLVM=1 Image dtb.img dtbo.img

    local kernel="${OUT_DIR}/arch/arm64/boot/Image"
    local dtb="${OUT_DIR}/arch/arm64/boot/dtb.img"
    local dtbo="${OUT_DIR}/arch/arm64/boot/dtbo.img"

    if [ -f "$kernel" ] && [ -f "$dtb" ] && [ -f "$dtbo" ]; then
        echo -e "\nKernel compiled succesfully! Zipping up...\n"
        echo -e "Cloning your custom AnyKernel3 from ${AK3_REPO}..."
        if ! git clone --depth=1 "$AK3_REPO" AnyKernel3; then
            echo -e "\nFailed to clone AnyKernel3! Aborting...\n"
            return 1
        fi
        cp "$kernel" "$dtb" "$dtbo" AnyKernel3/
        cd AnyKernel3
        zip -r9 "../$ZIPNAME" * -x .git Makefile README.md '*placeholder'
        cd ..
        rm -rf AnyKernel3 # Clean up after zipping
        echo -e "\n${BUILD_TYPE} build completed in $(( (SECONDS - START_TIME) / 60)) minute(s) and $(( (SECONDS - START_TIME) % 60)) second(s) !"
        echo "Zip available at: ${ZIPNAME}"
    else
        echo -e "\n${BUILD_TYPE} compilation failed!"
        return 1
    fi
    return 0
}


# --- Main Script ---

# Setup tools
if ! [ -d "$TC_DIR" ]; then
	echo "Custom clang not found! Cloning from https://github.com/ekqiplur/calang-clang.git..."
	if ! git clone --depth=1 https://github.com/ekqiplur/calang-clang.git "$TC_DIR"; then
		echo "Cloning failed! Aborting..."
		exit 1
	fi
fi
export PATH="$TC_DIR/bin:$PATH"

if [[ $1 = "-r" || $1 = "--regen" ]]; then
	make O=out ARCH=arm64 $DEFCONFIG savedefconfig
	cp out/defconfig "${DEFCONFIG_PATH}"
	echo -e "\nSuccessfully regenerated defconfig at ${DEFCONFIG_PATH}"
	exit
fi

if [[ $1 = "-c" || $1 = "--clean" ]]; then
	rm -rf out_*
    echo "Cleaned up build output directories."
    exit
fi

# Backup the original defconfig
cp "${DEFCONFIG_PATH}" "${DEFCONFIG_PATH}.bak"

# --- Build 1: KernelSU (using the default config) ---
KSU_ZIPNAME="KernullException-KSU-$(date '+%Y%m%d-%H%M').zip"
do_build "KernelSU" "out_ksu" "$KSU_ZIPNAME"
KSU_SUCCESS=$?


# --- Build 2: Vanilla ---
VANILLA_ZIPNAME="KernullException-Vanilla-$(date '+%Y%m%d-%H%M').zip"
# Modify defconfig for Vanilla build by removing KSU flag
echo "Temporarily modifying defconfig for Vanilla build..."
sed -i '/CONFIG_KSU=y/d' ${DEFCONFIG_PATH}
do_build "Vanilla" "out_vanilla" "$VANILLA_ZIPNAME"
VANILLA_SUCCESS=$?


# --- Summary ---
# The cleanup function will run automatically on exit
echo -e "\n================================================="
echo "Build process finished!"
echo "Total time: $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s)."

if [ $KSU_SUCCESS -eq 0 ]; then
    echo "KernelSU Zip: $KSU_ZIPNAME"
else
    echo "KernelSU build FAILED."
fi

if [ $VANILLA_SUCCESS -eq 0 ]; then
    echo "Vanilla Zip: $VANILLA_ZIPNAME"
else
    echo "Vanilla build FAILED."
fi

echo "================================================="

if [ $KSU_SUCCESS -ne 0 ] || [ $VANILLA_SUCCESS -ne 0 ]; then
    exit 1
fi

exit 0