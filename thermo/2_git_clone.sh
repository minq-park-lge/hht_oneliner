#!/bin/bash
TOP_DIR=$(pwd)
git clone https://github.com/NXP/matter.git -b release/v1.6.0-TE2 nxp_matter

cd nxp_matter
python3 ./scripts/checkout_submodules.py --shallow --platform nxp --recursive
source scripts/bootstrap.sh -p nxp
pip install pyyaml
third_party/nxp/nxp_matter_support/scripts/update_nxp_sdk.py --platform common
source third_party/nxp/nxp_matter_support/github_sdk/sdk_next/repo/mcuxsdk/mcux-env.sh
export ARMGCC_DIR=$(pwd)/.environment/cipd/packages/arm


#HHT code
cd examples/thermostat/nxp
git clone git@github.com:HT-IoT-Partner/thermostat_nxp_rt1060_v1_6_TE2.git src
cd src
git am 0001-linux-build.patch
