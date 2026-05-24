빌드가 정상적으로 성공해서 다행입니다. 요청하신 대로 환경 구축부터 상시 빌드까지 깔끔하게 관리할 수 있도록 3개의 쉘 스크립트로 분할하여 정리해 드립니다.

각 스크립트 파일 내용을 복사해서 생성하신 후, 실행 권한(`chmod +x 파일명.sh`)을 부여해 사용하시면 됩니다.

---

### 1. `prerequisite.sh` (최초 1회 환경 구축용)

> 호스트 PC의 필수 컴파일러(`gcc-12`), 라이브러리, Homebrew 패키지 및 가상환경 락 우회 설정을 담당합니다.

```bash
#!/bin/bash
set -e

echo "=================================================="
# 1. 호스트 시스템 필수 패키지 및 gcc-12 설치
# ==================================================
echo "[1/3] Updating system packages and installing GCC 12..."
sudo apt-get update && sudo apt-get install -y \
    gcc-12 g++-12 build-essential libffi-dev libssl-dev \
    libdbus-1-dev libglib2.0-dev libavahi-client-dev \
    libgirepository1.0-dev libcairo2-dev libreadline-dev

# ==================================================
# 2. Homebrew를 통한 Python 3.11 및 빌드 툴체인 관리
# ==================================================
echo "[2/3] Installing Python 3.11, CMake, and Ninja via Homebrew..."
brew install python@3.11 cmake ninja

# ==================================================
# 3. PEP 668 우회 및 로컬 심볼릭 링크 정렬
# ==================================================
echo "[3/3] Setting up local Python symlinks and West..."
mkdir -p "$HOME/.local/bin"
ln -sf /home/linuxbrew/.linuxbrew/bin/pip3.11 "$HOME/.local/bin/pip"
ln -sf /home/linuxbrew/.linuxbrew/bin/pip3.11 "$HOME/.local/bin/pip3"
ln -sf /home/linuxbrew/.linuxbrew/bin/python3.11 "$HOME/.local/bin/python"
ln -sf /home/linuxbrew/.linuxbrew/bin/python3.11 "$HOME/.local/bin/python3"

# 환경변수 반영
export PATH="$HOME/.local/bin:$PATH"
hash -r

# West 전역 설치 (가상환경 외부 차단 우회)
pip3 install west --break-system-packages

echo "=================================================="
echo " Prerequisite installation completed successfully! "
echo "=================================================="

```

---

### 2. `oneliner.sh` (전체 소스 다운로드 및 초기 패치 자동화)

> 레포지토리 클론, 서브모듈 동기화, 파트너 소스 다운로드 및 ZAP/update.py 경로 치환, 최초 1회 코드 생성을 자동 수행합니다.

```bash
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

```

---

### 3. `build.sh` (상시 코드 수정 후 반복 빌드용)

> 변경 사항 반영 시 인자값(`debug` 또는 `release`)을 주어 호출하는 통합 빌드 스크립트입니다.
> 디버그 플래그 오버라이드 및 이전에 생성했던 고속 닌자 래퍼(`-j16`) 스레드 할당 로직이 포함되어 있습니다.

```bash
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

```

#### 💡 상시 빌드 스크립트 실행 방법

* **디버그 빌드 시:** `./build.sh debug` (또는 인자 생략 시 기본 디버그로 작동)
* **릴리즈 빌드 시:** `./build.sh release`
