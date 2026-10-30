#!/bin/bash

set -euo pipefail

# fpga gen
export XILINXD_LICENSE_FILE=2100@localhost

pushd fpga
vivado -mode tcl -source create.tcl -tclargs build
popd

PROJECT_ROOT="$(pwd)"
XSA_DIR="${PROJECT_ROOT}/fpga/project_main"
XSA_FILE="${XSA_DIR}/project_main.xsa"
DTG_DIR="dtg"

source /tools/Xilinx/Vitis/2024.2/settings64.sh
