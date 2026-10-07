#!/bin/bash

set -euo pipefail

SOURCE_DIR="/tools/yocto/sources"
BUILD_DIR_NAME="yocto"
BUILD_DIR="${PROJECT_ROOT}/${BUILD_DIR_NAME}" 

mkdir -p "${BUILD_DIR_NAME}"
pushd "${BUILD_DIR_NAME}"
set +u
source "${SOURCE_DIR}/poky/oe-init-build-env" "${BUILD_DIR}"
set -u

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
gen-machineconf --hw-description "${PROJECT_ROOT}/${DTG_DIR}" -c conf -l conf/local.conf --machine-name project_main-zynq

echo 'MACHINE = "project_main-zynq"' >> conf/local.conf
bitbake core-image-minimal

bitbake xilinx-bootbin

