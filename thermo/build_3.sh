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
echo "Building in [${BUILD_MODE^^}] mode with NXP MCUBoot Signatures..."

# 1. 툴체인 및 환경 변수 로드
source scripts/activate.sh
source third_party/nxp/nxp_matter_support/github_sdk/sdk_next/repo/mcuxsdk/mcux-env.sh
export ARMGCC_DIR="${MATTER_ROOT}/.environment/cipd/packages/arm"

mkdir -p "$HOME/bin"
echo -e '#!/bin/sh\nexec '"${MATTER_ROOT}"'/.environment/cipd/packages/pigweed/bin/ninja -j16 "$@"' > "$HOME/bin/ninja"
chmod +x "$HOME/bin/ninja"
export PATH="$HOME/bin:${MATTER_ROOT}/.environment/cipd/packages/pigweed/bin:$PATH"
hash -r

# 2. 빌드 타깃별 최적화 스위칭 변수 세팅
EXTRA_ZEPHYR_ARGS=""
if [ "${BUILD_MODE}" = "debug" ]; then
    EXTRA_ZEPHYR_ARGS="-DCONFIG_DEBUG=y -DCONFIG_COMPILER_OPT=\"-Og -g\""
else
    EXTRA_ZEPHYR_ARGS="-DCONFIG_DEBUG=n -DCONFIG_COMPILER_OPT=\"-Os\""
fi

# 3. NXP 빌드 옵션 강제 주입 (부트로더 연동 및 RSA 서명 활성화)
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


# 4. PDF 절대 주소 기반 정밀 Binary 병합 공정 (Merged Bin 생성)
echo "=================================================================="
echo " Starting Binary Merge Process based on PDF Memory Layout "
echo "=================================================================="

OUT_ZEPHYR="${MATTER_ROOT}/out/zephyr"
OUT_MCUBOOT="${MATTER_ROOT}/out/modules/chip-module/mcuboot" # PDF 소스 경로 반영
MERGED_IMAGE="${MATTER_ROOT}/out/zephyr/merged.bin"

# 1) 파일 존재 여부 최종 검증 및 경로 바인딩
BOOT_SRC="${OUT_MCUBOOT}/mcuboot_opensource.bin"
APP_SRC="${OUT_ZEPHYR}/app_SIGNED.bin"
TAG_SRC="${OUT_ZEPHYR}/inittag.bin"

# 백업 경로 스캔 (빌드 서브시스템 버전에 따른 스위칭 예외 처리)
if [ ! -f "${BOOT_SRC}" ]; then BOOT_SRC="${OUT_ZEPHYR}/bootloader.bin"; fi
if [ ! -f "${APP_SRC}" ]; then APP_SRC="${OUT_ZEPHYR}/zephyr.signed.bin"; fi
if [ ! -f "${TAG_SRC}" ]; then TAG_SRC="${MATTER_ROOT}/examples/thermostat/nxp/zap/inittag.bin"; fi

# 필수 아티팩트 체크
if [ ! -f "${BOOT_SRC}" ] || [ ! -f "${APP_SRC}" ]; then
    echo "[❌ ERROR] Critical build files are missing. Check your compilation logs above."
    echo "Missing Check -> Bootloader: ${BOOT_SRC}, Application: ${APP_SRC}"
    exit 1
fi

# 2) 32MB 대용량 빈 플레이트 파일 생성 (0x60000000 ~ 0x62000000 전체 플래시 커버리지용 약 32MB 가상화)
echo "-> Allocating empty flash binary workspace..."
dd if=/dev/zero bs=1M count=32 of="${MERGED_IMAGE}"

# 3) PDF가 요구한 핵심 메모리 오프셋 주소 맵에 따른 바이너리 주입
# 🟦 Bootloader: Base Address 0x60000000 -> Offset: 0x0
echo "-> 1. Injecting MCUBoot (from ${BOOT_SRC}) to Offset 0x0 (Flash: 0x60000000)"
dd if="${BOOT_SRC}" of="${MERGED_IMAGE}" bs=1 seek=0 conv=notrunc

# 🟩 Signed App: Base Address 0x60040000 -> Offset: 0x40000 (262,144 Bytes)
echo "-> 2. Injecting Application (from ${APP_SRC}) to Offset 0x40000 (Flash: 0x60040000)"
dd if="${APP_SRC}" of="${MERGED_IMAGE}" bs=1 seek=262144 conv=notrunc

# 🟨 Init Tag (존재할 때만): Base Address 0x61FDE000 -> Offset: 0x1FDE000 (33,415,168 Bytes)
if [ -f "${TAG_SRC}" ]; then
    echo "-> 3. Injecting Init Tag (from ${TAG_SRC}) to Offset 0x1FDE000 (Flash: 0x61FDE000)"
    dd if="${TAG_SRC}" of="${MERGED_IMAGE}" bs=1 seek=33415168 conv=notrunc
else
    echo "[⚠️ WARNING] inittag.bin not found anywhere. Merged image will proceed without Init Tag."
fi

echo "=================================================================="
echo " [SUCCESS] PDF Compliant Flash Image Generated! "
echo " Saved Directory: ${MERGED_IMAGE} "
echo "=================================================================="
