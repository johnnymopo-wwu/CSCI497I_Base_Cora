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
