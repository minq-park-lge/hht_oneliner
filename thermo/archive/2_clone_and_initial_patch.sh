#!/bin/bash
set -e

# 현재 스크립트 실행 위치를 기준 루트로 잡음 (기본값: ~/nxp_matter)
TARGET_DIR="$HOME/nxp_matter"
echo "Target directory: ${TARGET_DIR}"

# 1. 레포지토리 클론 및 이동
if [ ! -d "${TARGET_DIR}" ]; then
    echo "[1/5] Cloning Matter repository..."
    git clone https://github.com/NXP/matter.git -b release/v1.6.0-TE2 "${TARGET_DIR}"
fi
cd "${TARGET_DIR}"
export MATTER_ROOT=$(pwd)

# 2. 서브모듈 동기화 및 부트스트랩 (가상환경 활성화)
echo "[2/5] Checking out submodules and bootstrapping..."
./scripts/checkout_submodules.py --shallow --platform nxp --recursive
source scripts/bootstrap.sh -p nxp
pip3 install west

# 3. NXP SDK 업데이트 및 툴체인 경로 바인딩
echo "[3/5] Updating NXP SDK..."
third_party/nxp/nxp_matter_support/scripts/update_nxp_sdk.py --platform common
source third_party/nxp/nxp_matter_support/github_sdk/sdk_next/repo/mcuxsdk/mcux-env.sh
export ARMGCC_DIR="${MATTER_ROOT}/.environment/cipd/packages/arm"

# 4. 파트너 소스 다운로드 및 하드코딩 경로 일괄 치환
echo "[4/5] Cloning partner source and patching paths..."
cd examples/thermostat/nxp/
if [ ! -d "src" ]; then
    git clone git@github.com:HT-IoT-Partner/thermostat_nxp_rt1060_v1_6_TE2.git src
fi

# ZAP 및 update.py 내부 경로 정렬 (슬래시 치환 안정화 적용)
sed -i 's|"..\\\\..\\\\mcuxsdk\\\\middleware\\\\matter\\\\src\\\\app\\\\zap-templates\\\\zcl\\\\zcl.json"|"../../../../src/app/zap-templates/zcl/zcl.json"|g' zap/thermostat_matter_wifi.zap
sed -i 's|"..\\\\..\\\\mcuxsdk\\\\middleware\\\\matter\\\\src\\\\app\\\\zap-templates\\\\app-templates.json"|"../../../../src/app/zap-templates/app-templates.json"|g' zap/thermostat_matter_wifi.zap
sed -i 's|"../../mcuxsdk/middleware/wifi_nxp"|"../../../../third_party/nxp/nxp_matter_support/github_sdk/sdk_next/repo/mcuxsdk/middleware/wifi_nxp"|g' src/update.py
sed -i 's|"deps/nxp_matter_support" : "../../mcuxsdk/middleware/matter/third_party/nxp/nxp_matter_support"|"deps/nxp_matter_support" : "../../../../third_party/nxp/nxp_matter_support"|g' src/update.py
sed -i 's|"deps/mcuxsdk": "../../mcuxsdk"|"deps/mcuxsdk": "../../../../third_party/nxp/nxp_matter_support/github_sdk/sdk_next/repo/mcuxsdk"|g' src/update.py
sed -i 's|"deps/nxp_matter":"../../mcuxsdk/middleware/matter"|"deps/nxp_matter":"../../../.."|g' src/update.py

python3 src/update.py

# 5. ZAP 툴체인 탐색 및 최초 코드 제너레이션
echo "[5/5] Executing ZAP code generation..."
cd "${MATTER_ROOT}"
export ZAP_INSTALL_PATH="${MATTER_ROOT}/.environment/cipd/packages/zap"
if [ ! -f "${ZAP_INSTALL_PATH}/zap-cli" ]; then 
    export ZAP_INSTALL_PATH="${MATTER_ROOT}/.environment/cipd/packages/pigweed/bin"
fi
python3 scripts/tools/zap/generate.py examples/thermostat/nxp/zap/thermostat_matter_wifi.zap

echo "=================================================="
echo " One-liner setup and path patching completed!    "
echo "=================================================="