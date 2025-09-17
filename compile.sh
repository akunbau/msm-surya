#!/usr/bin/env bash

# Deskripsi:
# Script untuk membangun kernel Linux, mengemasnya dengan AnyKernel3, dan mengunggah hasilnya ke Telegram.
# Prasyarat:
# - Dependensi: git, make, clang, curl, zip, aarch64-linux-gnu-, arm-linux-gnueabi-
# - File .env dengan variabel BOT_TOKEN dan CHAT_ID
# - Direktori kerja dengan source kernel yang valid
# - Clang terinstall pada path yang ditentukan (default: /home/ekqi/kernel/clang/clang21/bin)
# Cara penggunaan:
# 1. Buat file .env dengan format:
#    BOT_TOKEN=your_bot_token
#    CHAT_ID=your_chat_id
# 2. Jalankan: bash build_kernel.sh [defconfig]
# Contoh: bash build_kernel.sh surya_defconfig

set -euo pipefail

# Fungsi pembersihan untuk trap
cleanup() {
    echo "[$(date '+%F %T')] Membersihkan resource..."
    [ -f "$BUILD_LOG" ] && rm -f "$BUILD_LOG"
}

# Trap untuk menangani error dan sinyal
trap 'cleanup; telegram_send_message "Build FAILED: $DEFCONFIG"; [ -f "$BUILD_LOG" ] && telegram_send_document "$BUILD_LOG" "Build log (failed)"; exit 1' ERR
trap 'cleanup; echo "[$(date '+%F %T')] Build dibatalkan!"; exit 1' SIGINT SIGTERM

# 1. Pemeriksaan dependensi
for cmd in git make clang curl zip aarch64-linux-gnu-gcc arm-linux-gnueabi-gcc; do
    if ! command -v "$cmd" >/dev/null; then
        echo "[$(date '+%F %T')] Error: $cmd tidak ditemukan! Silakan install terlebih dahulu."
        exit 1
    fi
done

# 2. Muat file .env
if [ -f .env ]; then
    set -a
    source .env
    set +a
else
    echo "[$(date '+%F %T')] Error: File .env tidak ditemukan!"
    exit 1
fi

# 3. Validasi variabel lingkungan
: "${BOT_TOKEN:?Error: BOT_TOKEN tidak diatur}"
: "${CHAT_ID:?Error: CHAT_ID tidak diatur}"
CLANG_PATH="${CLANG_PATH:-/home/ekqi/kernel/clang/clang21/bin}"
if [ ! -d "$CLANG_PATH" ]; then
    echo "[$(date '+%F %T')] Error: CLANG_PATH ($CLANG_PATH) tidak valid atau direktori tidak ditemukan!"
    exit 1
fi
export PATH="$CLANG_PATH:$PATH"

# 4. Variabel dan informasi sistem
OS_INFO="$(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')"
KERNEL_VERSION="$(make kernelversion 2>/dev/null || echo "Unknown")"
CLANG_VERSION="$(clang --version | head -n1)"
LAST_COMMIT="$(git log -1 --pretty=format:"%h - %s" 2>/dev/null || echo "Unknown")"
BUILD_DATE="$(date +"%A, %d %B %Y %H:%M:%S")"
START_TIME=$(date +%s)

KERNEL_DIR=$(pwd)
ANYKERNEL_DIR="${KERNEL_DIR}/AnyKernel3"
OUTPUT_DIR="${KERNEL_DIR}/out"
ANYKERNEL_URL="https://github.com/ekqiplur/AnyKernel3.git"
DEFCONFIG="${1:-surya_defconfig}"
PACKAGE_NAME="Surya-Kernel-$(date +%Y%m%d-%H%M).zip"
BUILD_LOG="$OUTPUT_DIR/build.log"

# 5. Fungsi helper
log() { echo "[$(date '+%F %T')] $*" | tee -a "$BUILD_LOG"; }

telegram_send_message() {
    local message="$1"
    for i in {1..3}; do
        curl --max-time 30 -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
            -F chat_id="$CHAT_ID" -F text="$message" >/dev/null && return 0
        log "Gagal mengirim pesan ke Telegram, mencoba lagi ($i/3)..."
        sleep 5
    done
    log "Error: Gagal mengirim pesan ke Telegram setelah 3 percobaan!"
}

telegram_send_document() {
    local file="$1"
    local caption="${2:-Build artifact}"
    for i in {1..3}; do
        curl --max-time 30 -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendDocument" \
            -F chat_id="$CHAT_ID" -F document=@"$file" -F caption="$caption" >/dev/null && return 0
        log "Gagal mengunggah dokumen ke Telegram, mencoba lagi ($i/3)..."
        sleep 5
    done
    log "Error: Gagal mengunggah dokumen ke Telegram setelah 3 percobaan!"
}

# 6. Kirim pesan awal
MESSAGE="🚀 Build started
🖥️ OS: $OS_INFO
🌐 Kernel: $KERNEL_VERSION
🛠️ Clang: $CLANG_VERSION
📂 Clang Path: $CLANG_PATH
📅 Time: $BUILD_DATE"
telegram_send_message "$MESSAGE"

# 7. Unduh AnyKernel3 jika belum ada
if [ ! -d "${ANYKERNEL_DIR}" ]; then
    log "Mengunduh AnyKernel3 dari GitHub..."
    git clone --depth=1 "${ANYKERNEL_URL}" "${ANYKERNEL_DIR}" 2>&1 | tee -a "$BUILD_LOG"
fi

# 8. Bersihkan dan siapkan build
log "Membersihkan output sebelumnya..."
make O="$OUTPUT_DIR" mrproper 2>&1 | tee "$BUILD_LOG"

log "Membuat $DEFCONFIG..."
export ARCH=arm64
export SUBARCH=arm64
export KBUILD_BUILD_USER="ekqi"
export KBUILD_BUILD_HOST="ekqi-dev"
make O="$OUTPUT_DIR" "$DEFCONFIG" 2>&1 | tee -a "$BUILD_LOG"

# 9. Build kernel
log "Membangun kernel dengan -j$(nproc --all)..."
make -j$(nproc --all) O="$OUTPUT_DIR" CC=clang \
    LLVM=1 \
    CROSS_COMPILE=aarch64-linux-gnu- \
    CROSS_COMPILE_ARM32=arm-linux-gnueabi- 2>&1 | tee -a "$BUILD_LOG"

# 10. Verifikasi file hasil build
KERNEL_IMAGE="${OUTPUT_DIR}/arch/arm64/boot/Image.gz"
DTB="${OUTPUT_DIR}/arch/arm64/boot/dtb.img"
DTBO="${OUTPUT_DIR}/arch/arm64/boot/dtbo.img"
for file in "$KERNEL_IMAGE" "$DTB" "$DTBO"; do
    if [ ! -f "$file" ] || [ ! -s "$file" ]; then
        log "Error: File $file tidak ditemukan atau kosong!"
        exit 1
    fi
done

# 11. Package hasil build
log "Mengemas ke $PACKAGE_NAME..."
cd "${ANYKERNEL_DIR}"
find . -type f -not -path './.git/*' -not -path './.github/*' -not -path './modules/*' -not -path './patch/*' -not -path './ramdisk/*' -not -name '*.zip' | zip -r9 "${KERNEL_DIR}/${PACKAGE_NAME}" -@ 2>&1 | tee -a "$BUILD_LOG"
if [ ! -f "${KERNEL_DIR}/${PACKAGE_NAME}" ] || [ ! -s "${KERNEL_DIR}/${PACKAGE_NAME}" ]; then
    log "Error: Gagal membuat $PACKAGE_NAME atau file kosong!"
    exit 1
fi

# 12. Hitung durasi dan ukuran file
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
FILE_SIZE=$(du -h "${KERNEL_DIR}/${PACKAGE_NAME}" | cut -f1)

# 13. Unggah ke Telegram
telegram_send_document "${KERNEL_DIR}/${PACKAGE_NAME}" "📌 Commit: $LAST_COMMIT"
telegram_send_message "✅ Build complete ($DEFCONFIG)
⏱️ Duration: $((DURATION/60)) menit $((DURATION%60)) detik
📦 Size: $FILE_SIZE"

# 14. Selesai
log "✅ Build selesai!"
cleanup