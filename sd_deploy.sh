#!/bin/bash
#
# sd_deploy.sh -- push a built Yocto image to an SD card, with an
# optional new user and extra apt packages baked into the rootfs
# before it's ever written to the card.
#
# Always installs a native dev toolchain (python3, build-essential, make,
# plus what's needed to build kernel modules), and, if available, the
# headers/source for the *Yocto* kernel (from the kernel-devsrc package)
# so out-of-tree modules can be built on the board.
#
# Usage:
#   sudo ./sd_deploy.sh -d /dev/sdX [-m MACHINE] [-u USERNAME] [-p pkg1,pkg2,...] [-K KERNEL_VERSION]
#
# Examples:
#   sudo ./sd_deploy.sh -d /dev/sdb
#   sudo ./sd_deploy.sh -d /dev/sdb -m project_main-versal
#   sudo ./sd_deploy.sh -d /dev/sdb -u mowerj -p "vim,htop,net-tools,sudo"
#
# Kernel headers: run `bitbake kernel-devsrc` first. Debian's own
# linux-headers-* packages do NOT match the Yocto (linux-xlnx) kernel.
#
# WARNING: this script repartitions and reformats the target device
# entirely. Double-check the device node before running -- `lsblk`
# first if you're not certain which one your SD card actually is.

set -euo pipefail

MACHINE="project_main-zynq"
NEW_USER=""
PACKAGES=""
DEV=""
KVER=""

# Always installed. build-essential pulls in gcc, g++, make, libc6-dev.
# bc/bison/flex/libssl-dev/libelf-dev are needed for `make scripts prepare`
# in the kernel tree and for building out-of-tree modules.
BASE_PACKAGES="python3 python3-pip build-essential make bc bison flex libssl-dev libelf-dev kmod"

usage() {
    echo "Usage: $0 -d /dev/sdX [-m MACHINE] [-u USERNAME] [-p pkg1,pkg2,...] [-K KERNEL_VERSION]" >&2
    exit 1
}

while getopts "d:m:u:p:K:h" opt; do
    case "$opt" in
        d) DEV="$OPTARG" ;;
        m) MACHINE="$OPTARG" ;;
        u) NEW_USER="$OPTARG" ;;
        p) PACKAGES="$OPTARG" ;;
        K) KVER="$OPTARG" ;;
        h|*) usage ;;
    esac
done

[[ -z "$DEV" ]] && usage

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: must be run as root (needed for partitioning/mounting/chroot)." >&2
    exit 1
fi

if [[ ! -b "$DEV" ]]; then
    echo "ERROR: $DEV is not a block device." >&2
    exit 1
fi

PROJECT_ROOT="$(pwd)"
YOCTO_TMP="${PROJECT_ROOT}/yocto/tmp"
DEPLOY_DIR="${YOCTO_TMP}/deploy/images/${MACHINE}"
BOOT_SCR="${PROJECT_ROOT}/boot.scr"   # the archived, fixed script -- NOT the Yocto-generated one

for f in "${DEPLOY_DIR}/boot.bin" "${DEPLOY_DIR}/uImage" "${DEPLOY_DIR}/system.dtb" "$BOOT_SCR"; do
    if [[ ! -e "$f" ]]; then
        echo "ERROR: expected file not found: $f" >&2
        echo "Did build.sh complete successfully for MACHINE=${MACHINE}?" >&2
        exit 1
    fi
done

# Locate kernel-devsrc package (any of deb/ipk/rpm, whichever PACKAGE_CLASSES produced).
DEVSRC_PKG="$(find "${YOCTO_TMP}/deploy" \( -path '*/deb/*' -o -path '*/ipk/*' -o -path '*/rpm/*' \) \
                -name 'kernel-devsrc[-_]*' ! -name '*-dbg*' ! -name '*-dev[-_]*' 2>/dev/null | sort | tail -n1 || true)"
MODULES_TGZ="${DEPLOY_DIR}/modules-${MACHINE}.tgz"

echo "About to WIPE AND REPARTITION $DEV -- this destroys all data on it."
echo "Machine: $MACHINE"
[[ -n "$NEW_USER" ]] && echo "New user: $NEW_USER"
echo "Packages: $BASE_PACKAGES ${PACKAGES//,/ }"
if [[ -n "$DEVSRC_PKG" ]]; then
    echo "Kernel source: $DEVSRC_PKG"
else
    echo "Kernel source: NOT FOUND -- run 'bitbake kernel-devsrc' to include it (continuing without)."
fi
[[ -e "$MODULES_TGZ" ]] && echo "Kernel modules: $MODULES_TGZ"
lsblk "$DEV"
read -rp "Type the device name again to confirm (${DEV}): " CONFIRM
if [[ "$CONFIRM" != "$DEV" ]]; then
    echo "Confirmation did not match -- aborting." >&2
    exit 1
fi

BOOT_MNT="$(mktemp -d)"
ROOTFS_STAGE="$(mktemp -d)"
ROOTFS_MNT="$(mktemp -d)"
PKG_TMP="$(mktemp -d)"

# mktemp -d creates 0700 directories. rsync -a copies the stage dir's mode
# onto the SD card's root, which gave a drwx------ / on the board.
chmod 755 "$ROOTFS_STAGE"

cleanup() {
    # Unmount chroot bind-mounts first, then real mounts, ignoring
    # anything that wasn't actually mounted.
    umount "${ROOTFS_STAGE}/dev/pts" 2>/dev/null || true
    umount "${ROOTFS_STAGE}/proc" 2>/dev/null || true
    umount "${ROOTFS_STAGE}/sys" 2>/dev/null || true
    umount "${ROOTFS_STAGE}/dev" 2>/dev/null || true
    umount "$BOOT_MNT" 2>/dev/null || true
    umount "$ROOTFS_MNT" 2>/dev/null || true
    rmdir "$BOOT_MNT" "$ROOTFS_MNT" 2>/dev/null || true
    rm -rf "$PKG_TMP"
}
trap cleanup EXIT

# --- Partition and format ---
echo "=== Partitioning $DEV ==="
parted --script "$DEV" \
    mklabel msdos \
    mkpart primary fat32 1MiB 129MiB \
    mkpart primary ext4 129MiB 100% \
    set 1 boot on

if [[ "$DEV" =~ [0-9]$ ]]; then
    PART1="${DEV}p1"
    PART2="${DEV}p2"
else
    PART1="${DEV}1"
    PART2="${DEV}2"
fi

partprobe "$DEV" 2>/dev/null || blockdev --rereadpt "$DEV"
udevadm settle
for _ in $(seq 1 20); do
    [[ -b "$PART1" && -b "$PART2" ]] && break
    sleep 0.5
done
[[ -b "$PART1" && -b "$PART2" ]] || { echo "ERROR: partition nodes never appeared" >&2; exit 1; }

mkfs.vfat -F 32 -n BOOT "$PART1"
mkfs.ext4 -F -L rootfs "$PART2"

# --- Boot partition contents ---
echo "=== Copying boot files ==="
mount "$PART1" "$BOOT_MNT"
cp "${DEPLOY_DIR}/boot.bin"   "${BOOT_MNT}/BOOT.BIN"
cp "$BOOT_SCR"                "${BOOT_MNT}/boot.scr"
cp "${DEPLOY_DIR}/uImage"     "${BOOT_MNT}/uImage"
cp "${DEPLOY_DIR}/system.dtb" "${BOOT_MNT}/system.dtb"
umount "$BOOT_MNT"

# --- Root filesystem: debootstrap ---
echo "=== Building Debian rootfs (debootstrap, armhf, bookworm) ==="
if ! command -v debootstrap >/dev/null; then
    echo "ERROR: debootstrap not installed. Run: apt install debootstrap qemu-user-static binfmt-support" >&2
    exit 1
fi

debootstrap --arch=armhf --foreign bookworm "$ROOTFS_STAGE" http://deb.debian.org/debian
cp /usr/bin/qemu-arm-static "${ROOTFS_STAGE}/usr/bin/"
chroot "$ROOTFS_STAGE" /debootstrap/debootstrap --second-stage

echo "=== Set a root password for the target system ==="
chroot "$ROOTFS_STAGE" passwd root

# --- Bind-mount pseudo-filesystems + DNS for apt to work inside the chroot ---
mount --bind /proc "${ROOTFS_STAGE}/proc"
mount --bind /sys  "${ROOTFS_STAGE}/sys"
mount --bind /dev  "${ROOTFS_STAGE}/dev"
mount --bind /dev/pts "${ROOTFS_STAGE}/dev/pts"
cp /etc/resolv.conf "${ROOTFS_STAGE}/etc/resolv.conf"

# --- Packages (base + extra) ---
PKG_LIST="$BASE_PACKAGES ${PACKAGES//,/ }"
[[ -n "$NEW_USER" ]] && PKG_LIST="$PKG_LIST sudo"
echo "=== Installing packages: $PKG_LIST ==="
chroot "$ROOTFS_STAGE" apt-get update
# shellcheck disable=SC2086
chroot "$ROOTFS_STAGE" env DEBIAN_FRONTEND=noninteractive apt-get install -y $PKG_LIST

# --- Kernel modules (from Yocto) ---
if [[ -e "$MODULES_TGZ" ]]; then
    echo "=== Installing Yocto kernel modules ==="
    # --keep-directory-symlink: bookworm is merged-/usr (/lib -> usr/lib);
    # without it, tar would replace the /lib symlink with a real directory.
    tar --keep-directory-symlink -xzf "$MODULES_TGZ" -C "$ROOTFS_STAGE"
fi

# --- Kernel headers/source (from Yocto kernel-devsrc) ---
if [[ -n "$DEVSRC_PKG" ]]; then
    echo "=== Installing kernel source from $(basename "$DEVSRC_PKG") ==="
    case "$DEVSRC_PKG" in
        *.deb) dpkg-deb -x "$DEVSRC_PKG" "$PKG_TMP" ;;
        *.ipk) ( cd "$PKG_TMP" && ar x "$DEVSRC_PKG" && tar -xf data.tar.* && rm -f data.tar.* control.tar.* debian-binary ) ;;
        *.rpm) ( cd "$PKG_TMP" && rpm2cpio "$DEVSRC_PKG" | cpio -idm --quiet ) ;;
    esac
    if [[ ! -d "${PKG_TMP}/usr/src/kernel" ]]; then
        echo "WARNING: package did not contain usr/src/kernel; skipping kernel source." >&2
    else
        mkdir -p "${ROOTFS_STAGE}/usr/src"
        rsync -a "${PKG_TMP}/usr/src/kernel" "${ROOTFS_STAGE}/usr/src/"

        # Kernel version: -K, else from installed modules, else from Yocto pkgdata.
        if [[ -z "$KVER" ]]; then
            MODDIRS=( "${ROOTFS_STAGE}"/lib/modules/*/ )
            if [[ -d "${MODDIRS[0]}" && ${#MODDIRS[@]} -eq 1 ]]; then
                KVER="$(basename "${MODDIRS[0]}")"
            fi
        fi
        if [[ -z "$KVER" ]]; then
            ABIFILE="$(find "${YOCTO_TMP}/pkgdata" -path '*kernel-depmod/kernel-abiversion' 2>/dev/null | head -n1 || true)"
            [[ -n "$ABIFILE" ]] && KVER="$(cat "$ABIFILE")"
        fi

        if [[ -n "$KVER" ]]; then
            echo "Kernel version: $KVER"
            mkdir -p "${ROOTFS_STAGE}/lib/modules/${KVER}"
            ln -sfn /usr/src/kernel "${ROOTFS_STAGE}/lib/modules/${KVER}/build"
        else
            echo "WARNING: could not determine kernel version; /lib/modules/<ver>/build symlink not created." >&2
            echo "         Re-run with -K <version> (on the board: uname -r)." >&2
        fi

        # The kernel's helper programs (fixdep, modpost, ...) must be built
        # for ARM. This runs under qemu, so it takes a few minutes.
        echo "=== Preparing kernel tree for module builds (make scripts prepare, under qemu) ==="
        if ! chroot "$ROOTFS_STAGE" make -C /usr/src/kernel scripts prepare; then
            echo "WARNING: 'make scripts prepare' failed; run it on the board:" >&2
            echo "         cd /usr/src/kernel && sudo make scripts prepare" >&2
        fi
    fi
fi

# --- New user ---
if [[ -n "$NEW_USER" ]]; then
    echo "=== Creating user: $NEW_USER ==="
    chroot "$ROOTFS_STAGE" adduser "$NEW_USER"
    chroot "$ROOTFS_STAGE" usermod -aG sudo "$NEW_USER"
fi

chroot "$ROOTFS_STAGE" apt-get clean

# Unmount bind-mounts before rsync/cleanup
umount "${ROOTFS_STAGE}/dev/pts"
umount "${ROOTFS_STAGE}/proc"
umount "${ROOTFS_STAGE}/sys"
umount "${ROOTFS_STAGE}/dev"

echo "=== Writing rootfs to $PART2 ==="
mount "$PART2" "$ROOTFS_MNT"
rsync -aHAX "${ROOTFS_STAGE}/" "${ROOTFS_MNT}/"
chmod 755 "$ROOTFS_MNT"
umount "$ROOTFS_MNT"

rm -rf "$ROOTFS_STAGE"

echo ""
echo "=== Done. Safe to eject $DEV. ==="
