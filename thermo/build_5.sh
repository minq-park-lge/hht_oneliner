#!/bin/bash
# 사용법: ./build.sh debug 또는 ./build.sh release

POSTBUILD_DIR=($pwd)/postbuild.sh

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
echo "Building in [${BUILD_MODE^^}] mode..."

# 1. 환경 변수 및 서브시스템 툴체인 바인딩
source scripts/activate.sh
source third_party/nxp/nxp_matter_support/github_sdk/sdk_next/repo/mcuxsdk/mcux-env.sh
export ARMGCC_DIR="${MATTER_ROOT}/.environment/cipd/packages/arm"


# 1. 계산식: 코어 수 - 2 (단, 결과가 1 미만이면 1로 세팅)
CORES=$(nproc)
TARGET_JOBS=$(( CORES - 2 ))
if [ ${TARGET_JOBS} -le 0 ]; then
    TARGET_JOBS=1
fi

echo "Detected CPU Cores: ${CORES} -> Setting Ninja Jobs to: ${TARGET_JOBS}"


mkdir -p "$HOME/bin"
echo -e '#!/bin/sh\nexec '"${MATTER_ROOT}"'/.environment/cipd/packages/pigweed/bin/ninja -j$TARGET_JOBS "$@"' > "$HOME/bin/ninja"
chmod +x "$HOME/bin/ninja"
export PATH="$HOME/bin:${MATTER_ROOT}/.environment/cipd/packages/pigweed/bin:$PATH"
hash -r

# 2. 빌드 타깃별 최적화 스위칭 변수 세팅
EXTRA_ZEPHYR_ARGS=""
if [ "${BUILD_MODE}" = "debug" ]; then
    EXTRA_ZEPHYR_ARGS="-DCONFIG_DEBUG=y -DCONFIG_COMPILER_OPT=\"-Og\""
else
    EXTRA_ZEPHYR_ARGS="-DCONFIG_DEBUG=n -DCONFIG_COMPILER_OPT=\"-Os\""
fi

# 3. 메인 어플리케이션 컴파일 공정 (app.elf 생성 단계)
west build -p always -d "${MATTER_ROOT}/out" -b evkcmimxrt1060 examples/thermostat/nxp \
    -- \
    -DCONF_FILE="${MATTER_ROOT}/examples/thermostat/nxp/prj.conf" \
    -DNXP_MATTER_SUPPORT_DIR="${MATTER_ROOT}/third_party/nxp/nxp_matter_support" \
    -DCHIP_ROOT="${MATTER_ROOT}" \
    -DCONFIG_MCUX_COMPONENT_component.wifi_bt_module.IW61X="y" \
    -DCONFIG_MCUX_COMPONENT_component.wifi_bt_module.board_murata_2ll_m2="y" \
    -DCONFIG_CHIP_SE05X="y" \
    ${EXTRA_ZEPHYR_ARGS}

# 4. [핵심] 제공된 postbuild.sh를 활용한 서명 및 바이너리 추출 공정 연동
echo ""
echo "=================================================================="
echo " Running Custom Post-Build Script to extract Signed Components    "
echo "=================================================================="

# 경로 변수 매핑 처리 정의
BUILD_DIR="${MATTER_ROOT}/out/zephyr"
SDK_DIR="${MATTER_ROOT}/third_party/nxp/nxp_matter_support/github_sdk/sdk_next/repo/mcuxsdk"
POSTBUILD_SCRIPT=$POSTBUILD_DIR

if [ ! -f "${POSTBUILD_SCRIPT}" ]; then
    echo "[❌ ERROR] Cannot find postbuild.sh at $HOME/CCC/postbuild.sh"
    exit 1
fi

# postbuild.sh 실행 권한 강제 부여 후 트리거 작동
chmod +x "${POSTBUILD_SCRIPT}"
"${POSTBUILD_SCRIPT}" \
    --build-dir "${BUILD_IMAGE_DIR:-$BUILD_DIR}" \
    --sdk-dir "${SDK_DIR}" \
    --toolchain "${ARMGCC_DIR}" \
    --version "0.9.19"

# 5. 📂 PDF 스펙 및 postbuild 산출물 기반 정밀 Binary 병합 공정 (merged.bin)
echo ""
echo "=================================================================="
echo " Starting Binary Merge Process based on PDF Memory Layout         "
echo "=================================================================="

MERGED_IMAGE="${BUILD_DIR}/merged.bin"

# 포스트빌드가 떨군 최종 확정 타깃 매핑
BOOT_SRC="${BUILD_DIR}/modules/chip/mcuboot/mcuboot_opensource.bin"
APP_SRC="${BUILD_DIR}/app_SIGNED.bin"
TAG_SRC="${BUILD_DIR}/inittag.bin"

if [ ! -f "${BOOT_SRC}" ] || [ ! -f "${APP_SRC}" ] || [ ! -f "${TAG_SRC}" ]; then
    echo "[❌ ERROR] Post-build completed but some required binaries are missing!"
    echo "Check status -> Bootloader: $([ -f "$BOOT_SRC" ] && echo "OK" || echo "MISSING"), App: $([ -f "$APP_SRC" ] && echo "OK" || echo "MISSING"), Tag: $([ -f "$TAG_SRC" ] && echo "OK" || echo "MISSING")"
    exit 1
fi

# 32MB 가상화 베이스 필드 디바이스 생성
echo "-> Allocating empty flash workspace..."
dd if=/dev/zero bs=1M count=32 of="${MERGED_IMAGE}"

# 주소 매핑 강제 주입 공정
# 🟦 Bootloader: 0x60000000 -> Offset 0
echo "-> 1. Injecting mcuboot_opensource.bin to Flash Offset 0x0"
dd if="${BOOT_SRC}" of="${MERGED_IMAGE}" bs=1 seek=0 conv=notrunc

# 🟩 Signed App: 0x60040000 -> Offset 0x40000 (262,144 Bytes)
echo "-> 2. Injecting app_SIGNED.bin to Flash Offset 0x40000"
dd if="${APP_SRC}" of="${MERGED_IMAGE}" bs=1 seek=262144 conv=notrunc

# 🟨 Init Tag: 0x61FDE000 -> Offset 0x1FDE000 (33,415,168 Bytes)
echo "-> 3. Injecting inittag.bin to Flash Offset 0x1FDE000"
dd if="${TAG_SRC}" of="${MERGED_IMAGE}" bs=1 seek=33415168 conv=notrunc

echo "=================================================================="
echo " [SUCCESS] PDF Compliant Merged Image Created with Post-Build!    "
echo " Output Package Target: ${MERGED_IMAGE}                           "
echo "=================================================================="
