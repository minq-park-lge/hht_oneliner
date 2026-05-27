#!/bin/bash

#matter가 있는 디렉토리가 symlink일 경우 realpath를 찾아서 세팅해야함.
MATTER_ROOT=$(readlink -f $(pwd))
cd $MATTER_ROOT
SDK_NEXT_ROOT=$MATTER_ROOT/third_party/nxp/nxp_matter_support/github_sdk/sdk_next

#----------- make sure crc module installed
$home/bin/python -m pip install crc


#--------------------------------------
source scripts/activate.sh
source third_party/nxp/nxp_matter_support/github_sdk/sdk_next/repo/mcuxsdk/mcux-env.sh
export ARMGCC_DIR=$(pwd)/.environment/cipd/packages/arm

#------------------------------------------
mkdir -p ~/bin || true
rm ~/bin/ninja || true
echo "#!/bin/sh" >> ~/bin/ninja
echo "exec $MATTER_ROOT/.environment/cipd/packages/pigweed/bin/ninja -j$(nproc) \"\$@\"" >> ~/bin/ninja

cat ~/bin/ninja
chmod +x ~/bin/ninja
export PATH="$HOME/bin:$PATH"
hash -r
#-------------------------------------------------------------------------------------------------
# debug build
#주의2. 아래 제퍼베이스 디렉토리를 설정해야 west build -d (or --build-dir)가 동작함.
export ZEPHYR_BASE=$SDK_NEXT_ROOT/zephyr
echo "cur dir: $(pwd)"
set -x
west build --build-dir $MATTER_ROOT/out \
    -b evkcmimxrt1060 examples/thermostat/nxp \
    -DCONF_FILE="$MATTER_ROOT/examples/thermostat/nxp/prj.conf" \
    -DNXP_MATTER_SUPPORT_DIR="$MATTER_ROOT/third_party/nxp/nxp_matter_support" \
    -DCHIP_ROOT="$MATTER_ROOT" \
    -DCONFIG_MCUX_COMPONENT_component.wifi_bt_module.IW61X="y" \
    -DCONFIG_MCUX_COMPONENT_component.wifi_bt_module.board_murata_2ll_m2="y" \
    -DCONFIG_CHIP_SE05X="y"
set +x

cd $MATTER_ROOT/out
ls -ahl
