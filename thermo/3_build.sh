#!/bin/bash
# 사용법: ./build.sh debug 또는 ./build.sh release
set -e

# 1. 빌드 모드 입력값 검증 (인자값이 없으면 기본 debug)
BUILD_MODE=$(echo "${1:-debug}" | tr '[:upper:]' '[:lower:]')

if [ "${BUILD_MODE}" != "debug" ] && [ "${BUILD_MODE}" != "release" ]; then
    echo "Error: Invalid build mode. Use './build.sh debug' or './build.sh release'"
    exit 1
fi

# 2. 루트 경로 감지 및 가상환경 재활성화
if [ -z "${MATTER_ROOT}" ]; then
    if [ -d "$HOME/nxp_matter" ]; then
        cd "$HOME/nxp_matter"
    else
        echo "Error: MATTER_ROOT environment variable is not set, and ~/nxp_matter does not exist."
        exit 1
    fi
else
    cd "${MATTER_ROOT}"
fi

export MATTER_ROOT=$(pwd)
echo "Active MATTER_ROOT: ${MATTER_ROOT}"
echo "Starting build in [${BUILD_MODE^^}] mode..."

# 부트스트랩 가상환경 및 SDK 경로 환경 재로딩
source scripts/activate.sh
source third_party/nxp/nxp_matter_support/github_sdk/sdk_next/repo/mcuxsdk/mcux-env.sh
export ARMGCC_DIR="${MATTER_ROOT}/.environment/cipd/packages/arm"

# 3. 고속 빌드 전용 닌자 래퍼 스크립트 인라인 정렬
mkdir -p "$HOME/bin"
echo -e '#!/bin/sh\nexec '"${MATTER_ROOT}"'/.environment/cipd/packages/pigweed/bin/ninja -j16 "$@"' > "$HOME/bin/ninja"
chmod +x "$HOME/bin/ninja"

export PATH="$HOME/bin:${MATTER_ROOT}/.environment/cipd/packages/pigweed/bin:$PATH"
hash -r

# 4. 빌드 타깃별 빌드 옵션 스위칭 구성
# 디버그/릴리즈 플래그에 맞게 추가 오버라이드 변수를 설정합니다.
EXTRA_ZEPHYR_ARGS=""
if [ "${BUILD_MODE}" = "debug" ]; then
    EXTRA_ZEPHYR_ARGS="-DCONFIG_DEBUG=y -DCONFIG_COMPILER_OPT=\"-Og -g\""
else
    EXTRA_ZEPHYR_ARGS="-DCONFIG_DEBUG=n -DCONFIG_COMPILER_OPT=\"-Os\""
fi

# 5. West 컴파일 명령 수행 (Pristine build 설정 유지)
west build -p always -d "${MATTER_ROOT}/out" -b evkcmimxrt1060 examples/thermostat/nxp \
    -- \
    -DCONF_FILE="${MATTER_ROOT}/examples/thermostat/nxp/prj.conf" \
    -DNXP_MATTER_SUPPORT_DIR="${MATTER_ROOT}/third_party/nxp/nxp_matter_support" \
    -DCHIP_ROOT="${MATTER_ROOT}" \
    -DCONFIG_MCUX_COMPONENT_component.wifi_bt_module.IW61X="y" \
    -DCONFIG_MCUX_COMPONENT_component.wifi_bt_module.board_murata_2ll_m2="y" \
    -DCONFIG_CHIP_SE05X="y" \
    ${EXTRA_ZEPHYR_ARGS}

echo "=================================================="
echo " Build successful! Mode: [${BUILD_MODE^^}] "
echo " Output directory: ${MATTER_ROOT}/out "
echo "=================================================="