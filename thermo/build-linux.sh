#!/usr/bin/env bash

start_time=$(date)
set -e

# ------------------------------------------------------------
# find MATTER_ROOT (script 기준 + upward search)
# ------------------------------------------------------------
find_matter_root() {
    local start_dir="$1"
    local cur="$start_dir"

    while [ "$cur" != "/" ]; do
        if [ -d "$cur/third_party/nxp/nxp_matter_support" ] && \
           [ -d "$cur/scripts" ]; then
            echo "$cur"
            return 0
        fi
        cur="$(dirname "$cur")"
    done
    return 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

MATTER_ROOT="$(find_matter_root "$SCRIPT_DIR")" || \
MATTER_ROOT="$(find_matter_root "$(pwd -P)")" || {
    echo "ERROR: MATTER_ROOT not found"
    exit 1
}

echo "MATTER_ROOT = $MATTER_ROOT"

cd "$MATTER_ROOT"

SDK_NEXT_ROOT="$MATTER_ROOT/third_party/nxp/nxp_matter_support/github_sdk/sdk_next"
# ------------------------------------------------------------
# argument parsing
# ------------------------------------------------------------
MODE="${1:-debug}"   # default = debug

echo "BUILD MODE = $MODE"


# ------------------------------------------------------------
# clean
# ------------------------------------------------------------
if [ "$MODE" = "clean" ]; then
    echo "Cleaning build output..."
    rm -rf "$MATTER_ROOT/out"
    echo "done"
    exit 0
fi


# ------------------------------------------------------------
# regenerate .matter from .zap (codegen input 보장)
# ------------------------------------------------------------
echo "Generating .matter from .zap..."

python3 scripts/tools/zap/generate.py \
    examples/thermostat/nxp/zap/thermostat_matter_wifi.zap
# ------------------------------------------------------------
# common setup
# ------------------------------------------------------------
"$HOME/bin/python" -m pip install crc

source scripts/activate.sh
source "$SDK_NEXT_ROOT/repo/mcuxsdk/mcux-env.sh"

export ARMGCC_DIR="$MATTER_ROOT/.environment/cipd/packages/arm"
export ZEPHYR_BASE="$SDK_NEXT_ROOT/zephyr"

# ninja wrapper
mkdir -p "$HOME/bin"
cat > "$HOME/bin/ninja" <<EOF
#!/bin/sh
exec "$MATTER_ROOT/.environment/cipd/packages/pigweed/bin/ninja" -j\$(nproc) "\$@"
EOF

chmod +x "$HOME/bin/ninja"
export PATH="$HOME/bin:$PATH"
hash -r

# ------------------------------------------------------------
# build logic
# ------------------------------------------------------------

if [ "$MODE" = "release" ]; then
    # -------------------------
    # release build
    # -------------------------
    set -x
    west build -d "$MATTER_ROOT/out" \
        -b evkcmimxrt1060 examples/thermostat/nxp \
        --config release \
        -DCONF_FILE="$MATTER_ROOT/examples/thermostat/nxp/prj.conf" \
        -DNXP_MATTER_SUPPORT_DIR="$MATTER_ROOT/third_party/nxp/nxp_matter_support" \
        -DCHIP_ROOT="$MATTER_ROOT" \
        -DCONFIG_MCUX_COMPONENT_component.wifi_bt_module.IW61X="y" \
        -DCONFIG_MCUX_COMPONENT_component.wifi_bt_module.board_murata_2ll_m2="y" \
        -DCONFIG_CHIP_SE05X="y"
    set +x

else
    # -------------------------
    # debug build (default)
    # ./build.sh or ./build.sh debug
    # -------------------------
    set -x
    west build --build-dir "$MATTER_ROOT/out" \
        -b evkcmimxrt1060 examples/thermostat/nxp \
        -DCONF_FILE="$MATTER_ROOT/examples/thermostat/nxp/prj.conf" \
        -DNXP_MATTER_SUPPORT_DIR="$MATTER_ROOT/third_party/nxp/nxp_matter_support" \
        -DCHIP_ROOT="$MATTER_ROOT" \
        -DCONFIG_MCUX_COMPONENT_component.wifi_bt_module.IW61X="y" \
        -DCONFIG_MCUX_COMPONENT_component.wifi_bt_module.board_murata_2ll_m2="y" \
        -DCONFIG_CHIP_SE05X="y"
    set +x
fi

cd "$MATTER_ROOT/out"
ls -ahl

echo "========= finished ========="

echo "start: $start_time"
echo "end: $(date)"
