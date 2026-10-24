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
#   mkdir -p /home/mowerj/stage 
#   sudo STAGE_PARENT=/home/mowerj/stage ./sd_deploy.sh -d /dev/sdX 
#
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

# --- Host tool preflight (before anything destructive) ---
if ! command -v debootstrap >/dev/null; then
    echo "ERROR: debootstrap not installed. Run: sudo apt install debootstrap qemu-user-static" >&2
    exit 1
fi
# ARM binaries in the chroot run through qemu via binfmt_misc. Newer
# Debian/Ubuntu ship static qemu-user binaries and register them with the
# F (fix-binary) flag, in which case nothing needs copying into the chroot.
# Older setups use /usr/bin/qemu-arm-static without F, which must be copied in.
BINFMT=/proc/sys/fs/binfmt_misc/qemu-arm
if [[ ! -r "$BINFMT" ]] || ! grep -qx enabled "$BINFMT"; then
    echo "ERROR: no binfmt_misc handler for ARM binaries ($BINFMT)." >&2
    echo "Install one: sudo apt install qemu-user-static   (or: qemu-user qemu-user-binfmt)" >&2
    echo "then: sudo systemctl restart systemd-binfmt" >&2
    exit 1
fi
QEMU_INTERP="$(awk '/^interpreter/ {print $2}' "$BINFMT")"
QEMU_FIXBIN=""
grep -q '^flags:.*F' "$BINFMT" && QEMU_FIXBIN=1
if [[ -z "$QEMU_FIXBIN" && ! -x "$QEMU_INTERP" ]]; then
    echo "ERROR: binfmt interpreter $QEMU_INTERP not found." >&2
    exit 1
fi
echo "qemu: $QEMU_INTERP${QEMU_FIXBIN:+ (fix-binary, no copy needed)}"

# The rootfs is staged on the host first. It can't go in /tmp on systems
# where /tmp is a tmpfs mounted nodev/noexec (debootstrap needs to create
# /dev/null and run binaries there), and it needs ~1 GB+ of space.
STAGE_PARENT="${STAGE_PARENT:-/var/tmp}"
mkdir -p "$STAGE_PARENT"
if ! STAGE_OPTS="$(findmnt -no OPTIONS --target "$STAGE_PARENT")"; then
    echo "ERROR: could not determine mount options for $STAGE_PARENT." >&2
    exit 1
fi
if [[ ",$STAGE_OPTS," =~ ,(nodev|noexec), ]]; then
    echo "ERROR: $STAGE_PARENT is mounted with ${BASH_REMATCH[1]} (options: $STAGE_OPTS)." >&2
    echo "Pick another staging dir: sudo STAGE_PARENT=/some/dir $0 ..." >&2
    exit 1
fi
echo "Staging rootfs under: $STAGE_PARENT ($(df -h --output=avail "$STAGE_PARENT" | tail -1 | tr -d ' ') free)"

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
ROOTFS_STAGE="$(mktemp -d -p "$STAGE_PARENT" sd_deploy_rootfs.XXXXXX)"
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

# Unmount every partition of $DEV, wherever it's mounted (desktop
# automounters like udisks mount SD cards under /run/media as soon as
# they appear). Also turns off any swap on it.
unmount_all() {
    local p
    for p in $(lsblk -lnpo NAME "$DEV" | tail -n +2); do
        swapoff "$p" 2>/dev/null || true
        while findmnt -rn -S "$p" >/dev/null 2>&1; do
            umount "$p" || { echo "ERROR: could not unmount $p (in use?)" >&2; exit 1; }
        done
    done
}

# --- Partition and format ---
echo "=== Unmounting and wiping old partitions on $DEV ==="
unmount_all
# Erase filesystem signatures first. The new partitions land at the same
# offsets as the old ones, so without this the old FAT/ext4 would reappear
# and the automounter would grab them again before mkfs runs.
for p in $(lsblk -lnpo NAME "$DEV" | tail -n +2); do
    wipefs -a -q "$p" || true
done
wipefs -a -q "$DEV"

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

unmount_all
mkfs.vfat -F 32 -n BOOT "$PART1"
mkfs.ext4 -F -L rootfs "$PART2"
udevadm settle
unmount_all   # in case the automounter grabbed the fresh filesystems

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
debootstrap --arch=armhf --foreign bookworm "$ROOTFS_STAGE" http://deb.debian.org/debian
if [[ -z "$QEMU_FIXBIN" ]]; then
    # Kernel looks for the interpreter at this path *inside* the chroot.
    mkdir -p "${ROOTFS_STAGE}$(dirname "$QEMU_INTERP")"
    cp "$QEMU_INTERP" "${ROOTFS_STAGE}${QEMU_INTERP}"
fi
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

