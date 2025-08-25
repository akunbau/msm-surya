#!/bin/bash

# Skrip untuk build kernel Surya

# Hentikan jika terjadi error
set -e

# --- Variabel Utama ---
KERNEL_DIR=$(pwd)
ANYKERNEL_DIR="${KERNEL_DIR}/AnyKernel3"
# CLANG_DIR="${KERNEL_DIR}/clang"
OUTPUT_DIR="${KERNEL_DIR}/out"

# URL Repositori
# CLANG_URL="https://github.com/ekqiplur/clangapan.git"
ANYKERNEL_URL="https://github.com/ekqiplur/AnyKernel3.git"

# Konfigurasi Build
CONFIG="surya_defconfig"
export ARCH=arm64
export SUBARCH=arm64
export KBUILD_BUILD_USER="ekqi"
export KBUILD_BUILD_HOST="ekqi-dev"


# --- Persiapan ---

# Unduh clang jika direktori tidak ada
# if [ ! -d "${CLANG_DIR}" ]; then
#     echo ">> Direktori clang tidak ditemukan. Mengunduh dari GitHub..."
#     git clone --depth=1 "${CLANG_URL}" "${CLANG_DIR}"
# fi

# Unduh AnyKernel3 jika direktori tidak ada
if [ ! -d "${ANYKERNEL_DIR}" ]; then
    echo ">> Direktori AnyKernel3 tidak ditemukan. Mengunduh dari GitHub..."
    git clone --depth=1 "${ANYKERNEL_URL}" "${ANYKERNEL_DIR}"
fi

# Tambahkan clang ke PATH
# export PATH="${CLANG_DIR}/bin:${PATH}"
export PATH="/home/ekqi/greenforce-clang/bin:$PATH"


# --- Kompilasi Kernel ---

echo ">> Memulai kompilasi kernel..."

# Bersihkan sisa build sebelumnya
make O="${OUTPUT_DIR}" mrproper

# Terapkan konfigurasi
make O="${OUTPUT_DIR}" "${CONFIG}"

# Mulai proses build
make -j$(nproc --all) O="${OUTPUT_DIR}" \
    CC=clang \
    LLVM=1 \
    CROSS_COMPILE=aarch64-linux-gnu- \
    CROSS_COMPILE_ARM32=arm-linux-gnueabi- 2>&1 | tee log.txt

echo ">> Kompilasi kernel selesai."


# --- Pengemasan ---

echo ">> Mengemas hasil build ke dalam zip..."

# Path artefak hasil build
KERNEL_IMAGE="${OUTPUT_DIR}/arch/arm64/boot/Image.gz"
DTB="${OUTPUT_DIR}/arch/arm64/boot/dtb.img"
DTBO="${OUTPUT_DIR}/arch/arm64/boot/dtbo.img"

# Verifikasi file hasil build
if [ ! -f "${KERNEL_IMAGE}" ] || [ ! -f "${DTB}" ] || [ ! -f "${DTBO}" ]; then
    echo "!! File hasil build tidak ditemukan. Proses kompilasi mungkin gagal."
    exit 1
fi

# Salin artefak ke direktori AnyKernel3
cp "${KERNEL_IMAGE}" "${ANYKERNEL_DIR}/Image.gz"
cp "${DTB}" "${ANYKERNEL_DIR}/dtb.img"
cp "${DTBO}" "${ANYKERNEL_DIR}/dtbo.img"

# Buat file zip
cd "${ANYKERNEL_DIR}"
ZIP_NAME="Surya-Kernel-$(date +%Y%m%d-%H%M).zip"

# Mengemas dengan mengecualikan file/folder yang tidak perlu
zip -r9 "${KERNEL_DIR}/${ZIP_NAME}" . -x ".git*" ".github*" "modules/*" "patch/*" "ramdisk/*" "*.zip"

cd "${KERNEL_DIR}"

echo "✅ Selesai!"
echo "File zip siap di-flash: ${KERNEL_DIR}/${ZIP_NAME}"
