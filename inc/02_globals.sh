#!/bin/bash
# Put any global variable in this file
# With their default value

G_REV="git r$(git_getrev)"

G_VERBOSE=""
if [ -z $G_LOG_MODE ]; then
	G_LOG_MODE=0
fi

if [ -z $G_REALLY_VERBOSE ]; then
	G_REALLY_VERBOSE=1
elif [ $G_REALLY_VERBOSE -eq 1 ]; then
	G_VERBOSE="-v"
fi

# Resources directories
G_WORKDIR="${G_WORKDIR}"
G_SCRIPTDIR="${G_SCRIPTDIR}"
G_KEXTDIR="${G_SCRIPTDIR}/extra_kexts"
G_KERNDIR="${G_SCRIPTDIR}/kernels"
G_TWEAKSDIR="${G_SCRIPTDIR}/tweaks"
G_CHAMELEONDIR="${G_SCRIPTDIR}/chameleon"
G_CLOVERDIR="${G_SCRIPTDIR}/clover"
G_TMPDIR="${G_SCRIPTDIR}/tmp"

G_IN_ARG=""
G_OUT_ARG=""

# Input file extension
G_IN_EXT=""
# Output file extension
G_OUT_EXT=""

# Input file name (without extension)
G_IN_NAME=""
# Output file name (without extension)
G_OUT_NAME=""

G_IN_PATH=""
G_OUT_PATH=""

G_OSBUILD=""
G_OSVER=""
G_OSNAME=""

# Mountpoint names
G_NAME_ESP="esp"
G_NAME_ESD="esd"
G_NAME_BASE="base"
G_NAME_TARGET="target"

# Mountpoint paths
G_MOUNTS_DIR="/mnt/osx"
G_MOUNTP_ESP="${G_MOUNTS_DIR}/${G_NAME_ESP}"
G_MOUNTP_ESD="${G_MOUNTS_DIR}/${G_NAME_ESD}"
G_MOUNTP_BASE="${G_MOUNTS_DIR}/${G_NAME_BASE}"
G_MOUNTP_TARGET="${G_MOUNTS_DIR}/${G_NAME_TARGET}"

# Qemu NBD map status
G_NBD0_MAPPED=0
G_NBD1_MAPPED=0
G_NBD2_MAPPED=0

# Are we in management menu mode?
G_MEDIAMENU=0

# Are we in virtual device mode?
G_VIRTUALDEV=0
G_DISKFMT=""
G_IMAGESIZE=0

G_QCOW2="qcow2"
G_VDI="vdi"
G_VHD="vhd"
G_VMDK="vmdk"
G_RAW="raw"

G_MBR="msdos"
G_GPT="gpt"

G_MKRESCUEUSB=0

# Devices Paths
G_DEV_ESP=""
G_DEV_ESD=""
G_DEV_BASE=""
G_DEV_TARGET=""

G_DEV_NBD0="/dev/nbd0"
G_DEV_NBD1="/dev/nbd1"
G_DEV_NBD2="/dev/nbd2"