#!/bin/bash
# 사용법: ./build.sh debug 또는 ./build.sh release
set -e

BUILD_MODE=$(echo "${1:-debug}" | tr '[:upper:]' '[:lower:]')
if [ "${BUILD_MODE}" != "debug" ] && [ "${BUILD_MODE}" != "release" ]; then
    echo "Error: Use './build.sh debug' or './build.sh release'"
    exit 1
fi

if [ -z "${MATTER_ROOT}" ]; then
    cd "$HOME/nxp_matter" 2>/dev/null || cd "$(pwd)"
else
    cd "${MATTER_ROOT}"
fi

export MATTER_ROOT=$(pwd)
echo "Active MATTER_ROOT: ${MATTER_ROOT}"
echo "Building in [${BUILD_MODE^^}] mode with MCUBOOT Signing..."

# 1. 환경 변수 및 툴체인 로드
source scripts/activate.sh
source third_party/nxp/nxp_matter_support/github_sdk/sdk_next/repo/mcuxsdk/mcux-env.sh
export ARMGCC_DIR="${MATTER_ROOT}/.environment/cipd/packages/arm"

mkdir -p "$HOME/bin"
echo -e '#!/bin/sh\nexec '"${MATTER_ROOT}"'/.environment/cipd/packages/pigweed/bin/ninja -j16 "$@"' > "$HOME/bin/ninja"
chmod +x "$HOME/bin/ninja"
export PATH="$HOME/bin:${MATTER_ROOT}/.environment/cipd/packages/pigweed/bin:$PATH"
hash -r

# 2. 빌드 모드 최적화 플래그 세팅
EXTRA_ZEPHYR_ARGS=""
if [ "${BUILD_MODE}" = "debug" ]; then
    EXTRA_ZEPHYR_ARGS="-DCONFIG_DEBUG=y -DCONFIG_COMPILER_OPT=\"-Og\""
else
    EXTRA_ZEPHYR_ARGS="-DCONFIG_DEBUG=n -DCONFIG_COMPILER_OPT=\"-Os\""
fi

# 3. 핵심: 부트로더 및 서명 바이너리 생성 옵션 강제 주입 (-- 뒤에 배치)
west build -p always -d "${MATTER_ROOT}/out" -b evkcmimxrt1060 examples/thermostat/nxp \
    -- \
    -DCONF_FILE="${MATTER_ROOT}/examples/thermostat/nxp/prj.conf" \
    -DNXP_MATTER_SUPPORT_DIR="${MATTER_ROOT}/third_party/nxp/nxp_matter_support" \
    -DCHIP_ROOT="${MATTER_ROOT}" \
    -DCONFIG_MCUX_COMPONENT_component.wifi_bt_module.IW61X="y" \
    -DCONFIG_MCUX_COMPONENT_component.wifi_bt_module.board_murata_2ll_m2="y" \
    -DCONFIG_CHIP_SE05X="y" \
    -DCONFIG_BOOTLOADER_MCUBOOT=y \
    -DCONFIG_MCUBOOT_SIGN_SIGNATURE_TYPE_RSA=y \
    ${EXTRA_ZEPHYR_ARGS}

# 4. 바이너리 병합 공정 (Merged Bin 패키징)
echo "=================================================="
echo " Starting Binary Merge Process (NXP RT Layout)    "
echo "=================================================="

OUT_DIR="${MATTER_ROOT}/out/zephyr"
MERGED_IMAGE="${OUT_DIR}/merged.bin"

# 4MB 크기의 빈 가상 메모리 파일(0x00) 생성
dd if=/dev/zero bs=1K count=4096 of="${MERGED_IMAGE}"

# 1) Bootloader 결합 (Offset: 0x0)
# Zephyr MCUBoot 활성화 시 빌드 디렉토리 하위의 mcuboot/zephyr.bin 혹은 bootloader.bin으로 타깃팅됩니다.
BOOT_TARGET=""
if [ -f "${OUT_DIR}/bootloader.bin" ]; then
    BOOT_TARGET="${OUT_DIR}/bootloader.bin"
elif [ -f "${MATTER_ROOT}/out/mcuboot/zephyr/zephyr.bin" ]; then
    BOOT_TARGET="${MATTER_ROOT}/out/mcuboot/zephyr/zephyr.bin"
fi

if [ -n "${BOOT_TARGET}" ]; then
    echo "-> Merging Bootloader from ${BOOT_TARGET} at 0x0"
    dd if="${BOOT_TARGET}" of="${MERGED_IMAGE}" bs=1 seek=0 conv=notrunc
else
    echo "[⚠️ WARNING] Bootloader binary not found!"
fi

# 2) Init Tag 결합 (Offset: 0x6000 / 24576)
# 만약 빌드 산출물에 없으면 NXP 기본 템플릿 영역에서 스캔 시도
if [ -f "${OUT_DIR}/inittag.bin" ]; then
    echo "-> Merging inittag.bin at 0x6000"
    dd if="${OUT_DIR}/inittag.bin" of="${MERGED_IMAGE}" bs=1 seek=24576 conv=notrunc
else
    BACKUP_TAG="${MATTER_ROOT}/examples/thermostat/nxp/zap/inittag.bin"
    if [ -f "${BACKUP_TAG}" ]; then
        echo "-> Merging template inittag.bin at 0x6000"
        dd if="${BACKUP_TAG}" of="${MERGED_IMAGE}" bs=1 seek=24576 conv=notrunc
    fi
fi

# 3) Signed App 결합 (Offset: 0x8000 / 32768)
# Zephyr 서명 툴 작동 시 기본 이름은 'zephyr.signed.bin'으로 나옵니다.
APP_TARGET=""
if [ -f "${OUT_DIR}/app_SIGNED.bin" ]; then
    APP_TARGET="${OUT_DIR}/app_SIGNED.bin"
elif [ -f "${OUT_DIR}/zephyr.signed.bin" ]; then
    APP_TARGET="${OUT_DIR}/zephyr.signed.bin"
fi

if [ -n "${APP_TARGET}" ]; then
    echo "-> Merging Signed Application from ${APP_TARGET} at 0x8000"
    dd if="${APP_TARGET}" of="${MERGED_IMAGE}" bs=1 seek=32768 conv=notrunc
else
    echo "[❌ ERROR] Signed Application Image (app_SIGNED.bin / zephyr.signed.bin) is missing!"
    exit 1
fi

echo "=================================================="
echo " [SUCCESS] Flash Ready Image Created Completely!   "
echo " Final Bin Path: ${MERGED_IMAGE} "
echo "=================================================="
