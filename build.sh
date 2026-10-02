#!/bin/bash

set -euo pipefail

# fpga gen
source /tools/Xilinx/Vivado/2024.2/settings64.sh
export XILINXD_LICENSE_FILE=2100@localhost

pushd fpga
vivado -mode tcl -source create.tcl -tclargs build
popd

PROJECT_ROOT="$(pwd)"
XSA_DIR="${PROJECT_ROOT}/fpga/project_main"
XSA_FILE="${XSA_DIR}/project_main.xsa"
DTG_DIR="dtg"

source /tools/Xilinx/Vitis/2024.2/settings64.sh

mkdir -p ${PROJECT_ROOT}/${DTG_DIR}
xsct -eval "source /tools/Xilinx/Vitis/2024.2/scripts/xsct/sdtgen/sdtgen.tcl; sdtgen set_dt_param -xsa ${PROJECT_ROOT}/fpga/project_main/project_main.xsa -dir ${PROJECT_ROOT}/${DTG_DIR}; sdtgen generate_sdt"

if [[ -f "${XSA_FILE}" ]]; then
    echo "xsa done, continuing"
else
    echo "ERROR: no xsa found: ${XSA_FILE}"
    exit 1
fi

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

