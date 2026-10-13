#!/bin/bash
# Pre-clone the git repos the Yocto kernel build needs, into BitBake's cache layout.
# Run this once while you have network.
#
# Usage:  ./fetch_offline.sh [download_dir]
#         default download_dir = /tools/yocto/downloads

set -euo pipefail

DL_DIR="${1:-/tools/yocto/downloads}"
GIT2="${DL_DIR}/git2"

if ! mkdir -p "${GIT2}" 2>/dev/null || [[ ! -w "${GIT2}" ]]; then
    echo "ERROR: cannot write to ${DL_DIR}" >&2
    echo "Run once:  sudo mkdir -p ${DL_DIR} && sudo chown ${USER} ${DL_DIR}" >&2
    exit 1
fi
echo "Download cache: ${DL_DIR}"

# 1. Xilinx kernel (large, several GB)
NAME="github.com.Xilinx.linux-xlnx.git"
if [[ -d "${GIT2}/${NAME}" ]]; then
    echo "Already have ${NAME}"
else
    echo "Cloning linux-xlnx (this takes a while)..."
    rm -rf "${GIT2}/${NAME}.tmp"
    git clone --mirror https://github.com/Xilinx/linux-xlnx.git "${GIT2}/${NAME}.tmp"
    mv "${GIT2}/${NAME}.tmp" "${GIT2}/${NAME}"
fi

# 2. Yocto kernel-cache metadata (small)
NAME="git.yoctoproject.org.yocto-kernel-cache"
if [[ -d "${GIT2}/${NAME}" ]]; then
    echo "Already have ${NAME}"
else
    echo "Cloning yocto-kernel-cache..."
    rm -rf "${GIT2}/${NAME}.tmp"
    git clone --mirror https://git.yoctoproject.org/yocto-kernel-cache "${GIT2}/${NAME}.tmp"
    mv "${GIT2}/${NAME}.tmp" "${GIT2}/${NAME}"
fi

# Check that the kernel commit your build asks for is present
SRCREV="2b7f6f70a62a52a467bed030a27c2ada879106e9"
if git -C "${GIT2}/github.com.Xilinx.linux-xlnx.git" cat-file -e "${SRCREV}^{commit}" 2>/dev/null; then
    echo "OK: kernel commit ${SRCREV} found"
else
    echo "WARNING: kernel commit ${SRCREV} not found in the clone" >&2
fi

echo "Done."
