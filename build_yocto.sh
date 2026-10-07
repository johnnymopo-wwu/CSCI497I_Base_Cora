#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(pwd)"
SOURCE_DIR="/tools/yocto/sources"
BUILD_DIR_NAME="yocto"
BUILD_DIR="${PROJECT_ROOT}/${BUILD_DIR_NAME}"
DTG_DIR="${PROJECT_ROOT}/dtg"            # written by the FPGA script's sdtgen step

# fail fast, before any layer setup
if [[ ! -f "${DTG_DIR}/system-top.dts" ]]; then
    echo "ERROR: no system device tree in ${DTG_DIR}" >&2
    echo "Run the FPGA build script first." >&2
    exit 1
fi

mkdir -p "${BUILD_DIR_NAME}"
pushd "${BUILD_DIR_NAME}"
set +u
source "${SOURCE_DIR}/poky/oe-init-build-env" "${BUILD_DIR}"
set -u
echo 'DL_DIR = "/tools/yocto/downloads"' > conf/auto.conf

bitbake-layers remove-layer meta-yocto-bsp || true

bitbake-layers add-layer "${SOURCE_DIR}/meta-openembedded/meta-oe"
bitbake-layers add-layer "${SOURCE_DIR}/meta-openembedded/meta-python"
bitbake-layers add-layer "${SOURCE_DIR}/meta-openembedded/meta-networking"
bitbake-layers add-layer "${SOURCE_DIR}/meta-openembedded/meta-filesystems"
bitbake-layers add-layer "${SOURCE_DIR}/meta-virtualization"
bitbake-layers add-layer "${SOURCE_DIR}/meta-arm/meta-arm-toolchain"
bitbake-layers add-layer "${SOURCE_DIR}/meta-arm/meta-arm"
bitbake-layers add-layer "${SOURCE_DIR}/meta-openamp"
bitbake-layers add-layer "${SOURCE_DIR}/meta-xilinx/meta-microblaze"
bitbake-layers add-layer "${SOURCE_DIR}/meta-xilinx/meta-xilinx-core"
bitbake-layers add-layer "${SOURCE_DIR}/meta-xilinx/meta-xilinx-standalone"
bitbake-layers add-layer "${SOURCE_DIR}/meta-xilinx/meta-xilinx-standalone-sdt"
bitbake-layers add-layer "${SOURCE_DIR}/meta-xilinx/meta-xilinx-bsp"
bitbake-layers add-layer "${SOURCE_DIR}/meta-xilinx-tools"
bitbake-layers add-layer "${PROJECT_ROOT}/meta-project-main"

export PATH="/tools/yocto/sources/gen-machine-conf:${PATH}"
gen-machineconf --hw-description "${DTG_DIR}" -c conf -l conf/local.conf --machine-name project_main-zynq

grep -q '^MACHINE = "project_main-zynq"' conf/local.conf || \
    echo 'MACHINE = "project_main-zynq"' >> conf/local.conf

bitbake core-image-minimal
bitbake xilinx-bootbin

