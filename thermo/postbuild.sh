#!/usr/bin/env bash
# ===========================================================================
# postbuild.sh
#
# Linux post-build script: app.elf → app.bin / inittag.bin /
#                           app_SIGNED.bin / app.ota / mcuboot_opensource.bin
#
# Usage:
#   ./postbuild.sh [OPTIONS]
#
#   -b, --build-dir   DIR   Build output directory  (default: script parent)
#   -s, --sdk-dir     DIR   mcuxsdk root             (default: /opt/mcuxsdk)
#   -t, --toolchain   DIR   arm-none-eabi toolchain  (default: auto-detect)
#   -v, --version     VER   Image version string     (default: 0.9.19)
#       --vn          NUM   OTA version number       (default: 9019)
#   -h, --help              Show this help
#
# Example:
#   ./postbuild.sh \
#     --build-dir ~/my_thermostat/se05x_wifi_iw610_default_crypto_debug \
#     --sdk-dir   ~/mcuxsdk \
#     --version   0.9.19
# ===========================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults (adjust to your Linux layout)
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/../se05x_wifi_iw610_default_crypto_debug"
SDK_DIR="/opt/mcuxsdk"
TOOLCHAIN_DIR=""          # empty = auto-detect from PATH
VERSION="0.9.19"
VN="9019"
VENDOR_ID=4142            # -v 4142
PRODUCT_ID=8864           # -p 8864

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -b|--build-dir)  BUILD_DIR="$2"; shift 2 ;;
        -s|--sdk-dir)    SDK_DIR="$2";   shift 2 ;;
        -t|--toolchain)  TOOLCHAIN_DIR="$2"; shift 2 ;;
        -v|--version)    VERSION="$2";   shift 2 ;;
        --vn)            VN="$2";        shift 2 ;;
        -h|--help)
            sed -n '3,30p' "$0"
            exit 0
            ;;
        *) echo "[ERROR] Unknown option: $1"; exit 1 ;;
    esac
done

BUILD_DIR="$(realpath "$BUILD_DIR")"
SDK_DIR="$(realpath "$SDK_DIR")"

# ---------------------------------------------------------------------------
# Locate arm-none-eabi-objcopy
# ---------------------------------------------------------------------------
if [[ -n "$TOOLCHAIN_DIR" ]]; then
    OBJCOPY="${TOOLCHAIN_DIR}/bin/arm-none-eabi-objcopy"
elif command -v arm-none-eabi-objcopy &>/dev/null; then
    OBJCOPY="arm-none-eabi-objcopy"
else
    echo "[ERROR] arm-none-eabi-objcopy not found."
    echo "        Install arm-none-eabi toolchain or pass --toolchain DIR"
    exit 1
fi

# ---------------------------------------------------------------------------
# Locate Python (prefer mcuxsdk venv)
# ---------------------------------------------------------------------------
if [[ -x "${SDK_DIR}/venv/bin/python" ]]; then
    PYTHON="${SDK_DIR}/venv/bin/python"
elif command -v python3 &>/dev/null; then
    PYTHON="python3"
else
    PYTHON="python"
fi

# ---------------------------------------------------------------------------
# Paths derived from SDK_DIR
# ---------------------------------------------------------------------------
IMGTOOL_DIR="${SDK_DIR}/middleware/mcuboot_opensource/scripts"
ECDSA_KEY="${SDK_DIR}/middleware/mcuboot_opensource/boot/nxp_mcux_sdk/keys/sign-ecdsa-p256-priv.pem"
RSA_KEY="${SDK_DIR}/middleware/mcuboot_opensource/boot/nxp_mcux_sdk/keys/sign-rsa2048-priv.pem"
OTA_TOOL_DIR="${SDK_DIR}/middleware/matter/scripts/tools/nxp/ota"
BOOTLOADER_CONF="${SDK_DIR}/middleware/matter/third_party/nxp/nxp_matter_support/cmake/rt/rt1060/bootloader.conf"
MCUBOOT_EXAMPLE="${SDK_DIR}/examples/ota_examples/mcuboot_opensource"
MCUBOOT_BUILD_DIR="${BUILD_DIR}/modules/chip/mcuboot"

APP_ELF="${BUILD_DIR}/app.elf"
APP_BIN="${BUILD_DIR}/app.bin"
INITTAG_BIN="${BUILD_DIR}/inittag.bin"
APP_SIGNED_BIN="${BUILD_DIR}/app_SIGNED.bin"
APP_SIGNED_RSA_BIN="${BUILD_DIR}/app_SIGNED_RSA.bin"
APP_OTA="${BUILD_DIR}/app.ota"
MCUBOOT_ELF="${MCUBOOT_BUILD_DIR}/mcuboot_opensource.elf"
MCUBOOT_BIN="${MCUBOOT_BUILD_DIR}/mcuboot_opensource.bin"

# ---------------------------------------------------------------------------
# Sanity checks
# ---------------------------------------------------------------------------
echo "============================================================"
echo "  NXP RT1060 Post-Build Script (Linux)"
echo "============================================================"
echo "  BUILD_DIR   : ${BUILD_DIR}"
echo "  SDK_DIR     : ${SDK_DIR}"
echo "  OBJCOPY     : ${OBJCOPY}"
echo "  PYTHON      : ${PYTHON}"
echo "  VERSION     : ${VERSION}  (vn=${VN})"
echo "============================================================"

[[ -f "$APP_ELF" ]]       || { echo "[ERROR] app.elf not found: $APP_ELF";  exit 1; }
[[ -d "$IMGTOOL_DIR" ]]   || { echo "[ERROR] imgtool dir not found: $IMGTOOL_DIR"; exit 1; }
[[ -f "$ECDSA_KEY" ]]     || { echo "[ERROR] ECDSA key not found: $ECDSA_KEY"; exit 1; }
[[ -f "$RSA_KEY" ]]       || { echo "[ERROR] RSA key not found: $RSA_KEY"; exit 1; }
[[ -d "$OTA_TOOL_DIR" ]]  || { echo "[ERROR] OTA tool dir not found: $OTA_TOOL_DIR"; exit 1; }

# ===========================================================================
# STEP 1: ELF → app.bin  (exclude .flash_config .ivt .NVM .inittag)
# ===========================================================================
echo ""
echo "[1/4] Converting app.elf → app.bin ..."
"$OBJCOPY" -O binary \
    -R .flash_config -R .ivt -R .NVM -R .inittag \
    "$APP_ELF" "$APP_BIN"
echo "      OK → ${APP_BIN}"

# STEP 1b: Extract inittag.bin
echo "      Extracting inittag section → inittag.bin ..."
"$OBJCOPY" -O binary --only-section=.inittag "$APP_ELF" "$INITTAG_BIN"
echo "      OK → ${INITTAG_BIN}"

# ===========================================================================
# STEP 2: Sign with imgtool.py
#   - ECDSA-P256 → app_SIGNED.bin
#   - RSA-2048   → app_SIGNED_RSA.bin
#   - Copy app_SIGNED.bin → app.bin  (overwrites, as Windows build does)
# ===========================================================================
echo ""
echo "[2/4] Signing app.bin with imgtool.py ..."

IMGTOOL_ARGS=(
    --align 4
    --header-size 0x1000
    --pad-header
    --slot-size 0xE40000
    --max-sectors 3648
    --version "${VERSION}"
    --pad
    --confirm
)

pushd "$IMGTOOL_DIR" > /dev/null

echo "      ECDSA-P256 signing ..."
"$PYTHON" imgtool.py sign \
    --key "$ECDSA_KEY" \
    "${IMGTOOL_ARGS[@]}" \
    "$APP_BIN" "$APP_SIGNED_BIN"
echo "      OK → ${APP_SIGNED_BIN}"

echo "      RSA-2048 signing ..."
"$PYTHON" imgtool.py sign \
    --key "$RSA_KEY" \
    "${IMGTOOL_ARGS[@]}" \
    "$APP_BIN" "$APP_SIGNED_RSA_BIN"
echo "      OK → ${APP_SIGNED_RSA_BIN}"

popd > /dev/null

# Overwrite app.bin with signed binary (matches Windows build behaviour)
cp "$APP_SIGNED_BIN" "$APP_BIN"
echo "      app_SIGNED.bin → app.bin (overwrite)"

# ===========================================================================
# STEP 3: Generate OTA file
# ===========================================================================
echo ""
echo "[3/4] Generating OTA file ..."

pushd "$OTA_TOOL_DIR" > /dev/null

"$PYTHON" ota_image_tool.py create \
    -v "$VENDOR_ID" \
    -p "$PRODUCT_ID" \
    -vn "$VN" \
    -vs "${VERSION}" \
    -da sha256 \
    --app-input-file "$APP_SIGNED_BIN" \
    "$APP_OTA"

popd > /dev/null
echo "      OK → ${APP_OTA}"

# ===========================================================================
# STEP 4: Build MCUBoot and convert to binary
# ===========================================================================
echo ""
echo "[4/4] Building MCUBoot (mcuboot_opensource) ..."

# Locate ARMGCC_DIR
if [[ -n "$TOOLCHAIN_DIR" ]]; then
    ARMGCC_DIR="$TOOLCHAIN_DIR"
elif command -v arm-none-eabi-gcc &>/dev/null; then
    ARMGCC_DIR="$(dirname "$(dirname "$(command -v arm-none-eabi-gcc)")")"
else
    echo "[ERROR] Cannot determine ARMGCC_DIR. Pass --toolchain DIR"
    exit 1
fi

export ARMGCC_DIR

# west must be on PATH (or in the venv)
if [[ -x "${SDK_DIR}/venv/bin/west" ]]; then
    WEST="${SDK_DIR}/venv/bin/west"
elif command -v west &>/dev/null; then
    WEST="west"
else
    echo "[ERROR] 'west' command not found."
    echo "        Install via: pip install west"
    exit 1
fi

pushd "$SDK_DIR" > /dev/null
"$WEST" build \
    -d "$MCUBOOT_BUILD_DIR" \
    -b evkcmimxrt1060 \
    "$MCUBOOT_EXAMPLE" \
    -DCONF_FILE="$BOOTLOADER_CONF"
popd > /dev/null

echo "      Converting mcuboot_opensource.elf → .bin ..."
"$OBJCOPY" -O binary "$MCUBOOT_ELF" "$MCUBOOT_BIN"
echo "      OK → ${MCUBOOT_BIN}"

# ===========================================================================
# Summary
# ===========================================================================
echo ""
echo "============================================================"
echo "  Post-build complete. Output files:"
printf "  %-26s %s\n" "app.bin"               "$APP_BIN"
printf "  %-26s %s\n" "inittag.bin"            "$INITTAG_BIN"
printf "  %-26s %s\n" "app_SIGNED.bin"         "$APP_SIGNED_BIN"
printf "  %-26s %s\n" "app_SIGNED_RSA.bin"     "$APP_SIGNED_RSA_BIN"
printf "  %-26s %s\n" "app.ota"                "$APP_OTA"
printf "  %-26s %s\n" "mcuboot_opensource.bin" "$MCUBOOT_BIN"
echo "============================================================"
