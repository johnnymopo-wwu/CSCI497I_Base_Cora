#!/bin/bash
# rebuild_yocto.sh -- refresh an existing Yocto build after a new
# bitstream / XSA / sdtgen output in ./dtg. Run from the project root,
# after build_yocto.sh has been run at least once.
set -euo pipefail

PROJECT_ROOT="$(pwd)"
SOURCE_DIR="/tools/yocto/sources"
BUILD_DIR="${PROJECT_ROOT}/yocto"
DTG_DIR="${PROJECT_ROOT}/dtg"
# Isolated copy of dtg/ handed to gen-machineconf. The tool searches above
# the path it's given and trips over the copies Yocto keeps under yocto/tmp*;
# hw/ holds nothing else, so only one system-top.dts can be found. Keep it:
# the generated config points at it.
SDT_DIR="${PROJECT_ROOT}/hw/sdt"
MACHINE_NAME="project_main-zynq"

# Recipes that consume the hardware description. These names are a best
# guess for the meta-xilinx SDT flow; any that don't exist in your layers
# are skipped. Check with:
#   bitbake-layers show-recipes | grep -iE 'fsbl|bitstream|device-tree|bootbin'
HW_RECIPES="sdt-artifacts device-tree fsbl-firmware fsbl bitstream-extraction bitstream xilinx-bootbin"

if [[ ! -f "${DTG_DIR}/system-top.dts" ]]; then
    echo "ERROR: no system device tree in ${DTG_DIR}. Run the FPGA build script first." >&2
    exit 1
fi
if [[ ! -f "${BUILD_DIR}/conf/local.conf" ]]; then
    echo "ERROR: ${BUILD_DIR} not set up. Run build_yocto.sh first." >&2
    exit 1
fi

set +u
source "${SOURCE_DIR}/poky/oe-init-build-env" "${BUILD_DIR}" >/dev/null
set -u
export PATH="${SOURCE_DIR}/gen-machine-conf:${PATH}"

# Regenerate the machine config from the new SDT.
mkdir -p "${SDT_DIR}"
rsync -a --delete "${DTG_DIR}/" "${SDT_DIR}/"
cp conf/local.conf conf/local.conf.bak
gen-machineconf --hw-description "${SDT_DIR}" -c conf -l conf/local.conf --machine-name "${MACHINE_NAME}"
grep -q "^MACHINE = \"${MACHINE_NAME}\"" conf/local.conf || \
    echo "MACHINE = \"${MACHINE_NAME}\"" >> conf/local.conf

# Force the hardware-dependent recipes to rebuild. Their inputs are files
# outside the layers, so bitbake's checksums may not see that they changed.
CLEAN=""
for r in $HW_RECIPES; do
    if bitbake-layers show-recipes "$r" 2>/dev/null | grep -q "^${r}:"; then
        CLEAN="$CLEAN $r"
    fi
done
echo "=== cleansstate:${CLEAN:- (none found)} ==="
# shellcheck disable=SC2086
[[ -n "$CLEAN" ]] && bitbake -c cleansstate $CLEAN

# Only what sd_deploy.sh uses: BOOT.BIN, uImage, system.dtb.
bitbake xilinx-bootbin virtual/kernel device-tree

DEPLOY="${BUILD_DIR}/tmp/deploy/images/${MACHINE_NAME}"
echo "=== Deploy outputs (check the timestamps are new) ==="
ls -l --time-style=+'%Y-%m-%d %H:%M:%S' "${DEPLOY}/boot.bin" "${DEPLOY}/system.dtb" "${DEPLOY}/uImage"
echo "local.conf diff vs. previous:"
diff conf/local.conf.bak conf/local.conf || true
