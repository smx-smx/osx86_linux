#!/bin/bash
set -e

err_report() {
	local r=$?
	if [ ! $r -eq 0 ]; then
		$lred; echo "Error on $0:$1"; $normal
	fi
	exit $r
}

trap 'err_report "$LINENO"' ERR
trap err_exit SIGINT

# These 2 variables need to be defined before we include the rest
G_WORKDIR="$(pwd -P)"
G_SCRIPTDIR="$( dirname "$( readlink -f "$0" )" )"
cd $G_SCRIPTDIR

for i in $G_SCRIPTDIR/inc/*.sh; do
	source "$i"
done

function do_cleanup(){
	local result
	for((i=0; i<3; i++)); do
		$yellow; echo "Trying to cleanup..."; $normal
		cleanup
		result=$?
		if [ $result -eq 0 ]; then
			break
		else
			sleep 1
		fi
	done
	if [ ! $result -eq 0 ]; then
		$lred; echo "Cleanup failed!"; $normal
	fi
	return $result
}

function cleanup() {
	sync
	if [ ! "${G_TMPDIR}" == "/tmp" ] && [ -d "${G_TMPDIR}" ]; then
		rm -r "${G_TMPDIR}"
	fi

	local result=0
	if [ -d /mnt/osx ]; then
		for mountpoint in esp base esd target; do
			while grep -q "$mountpoint" /proc/mounts; do
				$yellow; echo "umount ${G_MOUNTS_DIR}/${mountpoint}"; $normal
				if ! umount "${G_MOUNTS_DIR}/${mountpoint}"; then
					sleep 1
				fi
				result=$?
			done
			if [ -d "${G_MOUNTS_DIR}/${mountpoint}" ] && isEmpty "${G_MOUNTS_DIR}/${mountpoint}"; then
				rmdir "${G_MOUNTS_DIR}/${mountpoint}"
			else
				result=1
			fi
		done

		if isEmpty "${G_MOUNTS_DIR}"; then
			rmdir "${G_MOUNTS_DIR}"
		else
			$lyellow
			echo "${G_MOUNTS_DIR} is not empty!"
			echo "Some partitions couldn't be unmounted. Check what's accessing them and unmount them manually"
			$normal

			result=1
		fi
	fi

	qemu_umount_all
	qemu_unmap_all

	if [ -b /dev/nbd0 ]; then
		if ! rmmod nbd; then
			$lred; echo "WARNING: Cannot unload nbd"; $normal
		fi
	fi

	return $result
}

function usage(){
	echo "Osx Installer/Utilities for Linux by SMX"
	printf "$0 [dmgfile] [dev]\t\tConverts and install a dmg to a device\n"
	printf "$0 [dmgfile] [img file]\t\tConverts and install and create an img file\n"
	printf "$0 [dmgfile] [vdi/vmdk/vhd]\tConverts and install and create a virtual hard disk\n"
	printf "$0 [img file/vdi/vmdk/vhd]\tOpen the setup management/tweak menu\n"
	printf "$0 [pkg/mpkg] [destdir]\t\tExtract a package to destdir\n"
	printf "$0 [dev]\t\t\t\tShow Management Menu for setup media\n"
	printf "$0 --mkchameleon [dev]\t\tMakes chameleon rescue USB\n"
	printf "Management menu:\n"
	printf "\t-Install/Remove extra kexts\n"
	printf "\t-Install/Remove chameleon Modules\n"
	printf "\t-Install/Remove extra kernels\n"
	printf "\t-Install/Reinstall chameleon\n"
	printf "\t-Install/Reinstall mbr patch\n"
	printf "\t-Install/Reinstall custom smbios\n"
	printf "\t-Install/Reinstall custom DSDT\n"
	printf "\t-Apply tweaks/workarounds\n"
	printf "\t-Erase the whole setup partition\n"
}

function main(){
	$lgreen; printf "OSX Install Media Maker by "
	$lyellow; printf "S"
	$lblue; printf "M"
	$lpurple; printf "X\n"
	$normal

	echo "Version: ${G_REV}"

	if [ $# == 0 ] ||
	[ "$1" == "-h" ] ||
	[ "$1" == "--help" ] ||
	[ "$1" == "help" ] ||
	[ "$1" == "?" ] ||
	[ "$1" == "/?" ]
	then
		$white; usage; $normal
		err_exit ""
	fi

	if [ -z $SUDO_USER ]; then
		export SUDO_USER="root"
	fi

	if [ ! -d "${G_TMPDIR}" ]; then
		mkdir -p "${G_TMPDIR}"
	fi

	export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:${G_SCRIPTDIR}/bins/lib

	check_commands	#check that all required commands exist
	find_cmd "xar" "${G_SCRIPTDIR}/bins/bin"
	find_cmd "dmg2img" "${G_SCRIPTDIR}/bins/bin"
	find_cmd "pbzx" "${G_SCRIPTDIR}/bins/bin"
	find_cmd "kconfig_mconf" "${G_SCRIPTDIR}/bins/bin" "kconfig-mconf"
	find_cmd "mount_hfs" "${G_SCRIPTDIR}/bins/bin" "darling-dmg"

	G_IN_ARG="$1"
	G_OUT_ARG="$2"

	local name=$(basename "${G_IN_ARG}") #input
	G_IN_EXT=".${name##*.}"
	G_IN_NAME="${name%.*}"

	name=$(basename "${G_OUT_ARG}") #output
	G_OUT_EXT=".${name##*.}"
	G_OUT_NAME="${name%.*}"
	unset name

	docheck_kconfig
	load_config

	if is_on DEP_XAR; then
		docheck_xar
	fi
	if is_on DEP_DMG2IMG; then
		docheck_dmg2img
	fi
	if is_on DEP_PBZX; then
		docheck_pbzx
	fi
	if is_on DEP_DARLING_DMG; then
		docheck_darlingdmg
	fi

	$green
	echo "== External Dependencies =="
	$white
	is_on DEP_XAR         && echo "xar           => ${xar}"
	is_on DEP_DMG2IMG     && echo "dmg2img       => ${dmg2img}"
	is_on DEP_PBZX        && echo "pbzx          => ${pbzx}"
	is_on DEP_KCONFIG     && echo "kconfig-mconf => ${kconfig_mconf}"
	is_on DEP_DARLING_DMG && echo "mount_hfs     => ${mount_hfs}"
	$normal
	if (is_on DEP_XAR && [ ! -f "${xar}" ]) ||
		(is_on DEP_DMG2IMG && [ ! -f "${dmg2img}" ]) ||
		(is_on DEP_PBZX && [ ! -f "${pbzx}" ]) ||
		(is_on DEP_KCONFIG && [ ! -f "${kconfig_mconf}" ]) ||
		(is_on DEP_DARLING_DMG && [ ! -f "${mount_hfs}" ])
	then
		err_exit "Invalid dependencies, cannot continue!\n"
	fi

	if [ "${G_IN_EXT}" == ".pkg" ] || [ "${G_IN_EXT}" == ".mpkg" ]; then #./install_osx.sh [file.pkg/mpkg]
		if [ -z "${G_OUT_ARG}" ]; then #no dest dir
			usage
			err_exit "Invalid Destination Folder\n"
		fi
		extract_pkg "${G_IN_ARG}" "${G_OUT_ARG}"
		do_cleanup
		exit 0
	fi

	G_IN_PATH="$(dirname "$(readlink -f "${G_IN_ARG}")")"
	G_OUT_PATH="$(dirname "$(readlink -f "${G_OUT_ARG}")")"
	
	[ -z "${G_IN_PATH}" ] && err_exit "Cannot resolve absolute path for input \"${G_IN_ARG}\"\n"
	[ -z "${G_OUT_PATH}" ] && err_exit "Cannot resolve absolute path for output \"${G_OUT_ARG}\"\n"

	do_cleanup || exit 1

	# Create working dir
	if [ ! -d "${G_MOUNTS_DIR}" ]; then mkdir -p "${G_MOUNTS_DIR}"; fi
	# Create ESP mountpoint
	if [ ! -d "${G_MOUNTP_ESP}" ]; then mkdir "${G_MOUNTP_ESP}"; fi
	# Create ESD mountpoint
	if [ ! -d "${G_MOUNTP_ESD}" ]; then mkdir "${G_MOUNTP_ESD}"; fi
	# Create BaseSystem mountpoint
	if [ ! -d "${G_MOUNTP_BASE}" ]; then mkdir "${G_MOUNTP_BASE}"; fi
	# Create target mountpoint
	if [ ! -d "${G_MOUNTP_TARGET}" ]; then mkdir "${G_MOUNTP_TARGET}"; fi

	do_init_qemu

	G_IMAGESIZE=$3 #for img creation

	if [[ ! "$OSTYPE" == linux* ]]; then
		err_exit "This script can only be run under Linux\n"
	fi

	if [ ! ${EUID} -eq 0 ]; then
	   err_exit "This script must be run as root\n"
	fi

	if [ -b "${G_IN_ARG}" ] &&
		[ ! -f "${G_IN_ARG}" ] &&
		[ ! -d "${G_IN_ARG}" ] &&
		[ -z "${G_OUT_ARG}" ] &&
		[ -z "$3" ]
	then #./install_osx.sh [dev]
		dev_target="${G_IN_ARG}"
		mediamenu
	elif [ -f "${G_IN_ARG}" ] && [ -z "${G_OUT_ARG}" ] && [ -z "$3" ]; then #./install_osx.sh [file]
		if [ "${G_IN_EXT}" == ".dmg" ]; then #./install_osx.sh [file.dmg]
			usage
			err_exit "You must specify a valid target drive or image\n"
		elif [ "${G_IN_EXT}" == ".img" ] ||
			[ "${G_IN_EXT}" == ".hdd" ] ||
			[ "${G_IN_EXT}" == ".vhd" ] ||
			[ "${G_IN_EXT}" == ".vdi" ] ||
			[ "${G_IN_EXT}" == ".vmdk" ]
		then #./install_osx.sh [file.img]
			G_VIRTUALDEV=1
		fi
	elif [ ! -b "${G_IN_ARG}" ] &&
		[ ! -f "${G_IN_ARG}" ] &&
		[ ! -d "${G_IN_ARG}" ] &&
		[ -z "${G_OUT_ARG}" ] &&
		[ -z "$3" ]
	then
		err_exit "No such device\n"
	fi

	local img_ext
	if [ ${G_VIRTUALDEV} -eq 1 ]; then
		img_ext="${G_IN_EXT}"
	else
		img_ext="${G_OUT_EXT}"
	fi

	case "${img_ext}" in
		.vdi)
			G_DISKFMT="vdi"
			;;
		.vhd)
			G_DISKFMT="vhd"
			;;
		.vmdk)
			G_DISKFMT="vmdk"
			;;
		.hdd|.img)
			G_DISKFMT="raw"
			;;
	esac

	if [ ${G_VIRTUALDEV} -eq 1 ]; then	
		mediamenu
	fi

	if [ ! "${G_IN_EXT}" == ".dmg" ] && [ ! "${G_IN_EXT}" == ".img" ]; then
			if [ "$1" == "--mkchameleon" ]; then
				G_MKRESCUEUSB=1
			else
				usage
				err_exit "Invalid file specified\n"
			fi
	fi

	if [ -z "${G_OUT_ARG}" ]; then
		usage
		err_exit "You must specify a valid target drive or image\n"
	fi

	if [ ! -b "${G_OUT_ARG}" ]; then
		if [ "${G_OUT_EXT}" == ".img" ] ||
			[ "${G_OUT_EXT}" == ".hdd" ] ||
			[ "${G_OUT_EXT}" == ".vhd" ] ||
			[ "${G_OUT_EXT}" == ".vdi" ] ||
			[ "${G_OUT_EXT}" == ".vmdk" ]
		then
			vdev_check #switch to Virtual HDD mode & check
		fi
	fi

	G_DEV_TARGET="${G_OUT_ARG}"

	if [[ ${G_IN_ARG} == "/dev/sr[0-9]" ]]; then
		$lgreen; echo "CD Source Device Detected"; $normal
		if [ -z "${G_OUT_ARG}" ]; then
			err_exit "You must specify a valid destination to create an img file\n"
		elif [ -f "${G_OUT_ARG}" ]; then
			err_exit "${G_OUT_ARG} already exists\n"
		else
			$yellow; echo "Image creation is in progress..."
			echo "The process may take some time"; $normal
			if [ ! -d "$(dirname "${G_OUT_ARG}")" ] && ! mkdir -p "$(dirname "${G_OUT_ARG}")"; then
				err_exit "Can't create destination folder\n"
			fi
			dd if="${G_IN_ARG}" of="${G_OUT_ARG}"
			watch -n 10 kill -USR1 `pidof dd`
		fi
	fi

	do_preptarget
	if [ ${G_MKRESCUEUSB} -eq 1 ]; then
		do_finalize
		err_exit ""
	fi

	if is_on DRV_HFSPLUS; then
		local outfile="${G_IN_PATH}/${G_IN_NAME}.img"
		if [ ! -e "${outfile}" ]; then
			if is_on DEP_DMG2IMG; then
				echo "Converting ${G_IN_ARG} to img..."
				if ! $dmg2img "${G_IN_ARG}" "${outfile}" || [ ! -f "${outfile}" ]; then
					rm "${outfile}"
					err_exit "Img conversion failed\n"
				fi
			else
				err_exit "Enable dmg2img to convert to img!\n"
			fi
		fi

		$lyellow; echo "Mapping ${G_NAME_ESD} ($outfile) with qemu..."; $normal
		if [ ${G_NBD1_MAPPED} -eq 0 ]; then
			if ! qemu_map "1" "${outfile}"; then
				err_exit "Error during image mapping\n"
			fi
		fi
		G_DEV_ESD="${G_DEV_NBD1}"
	else #DRV_HFSPLUS
		G_DEV_ESD="${G_IN_ARG}" #Take the esd as is (darling-dmg)
	fi

	$yellow; echo "Mounting Partitions..."; $normal

	if is_on DRV_HFSPLUS; then
		# Try to mount ESD
		local part_dev=$(find_first_hfsplus_part "${G_DEV_ESD}")
		if [ -z "${part_dev}" ]; then
			err_exit "Cannot find a valid hfsplus partition in ${G_NAME_ESD}"
		fi
		if ! mount_part "${part_dev}" "${G_NAME_ESD}"; then
			err_exit "Cannot mount ${G_NAME_ESD}\n"
		fi
		G_DEV_ESD="${part_dev}"
	elif ! mount_part "${G_DEV_ESD}" "${G_NAME_ESD}"; then #DRV_DARLINGDMG
		err_exit "Cannot mount ${G_NAME_ESD}\n"
	fi

	if is_splitted; then
		if is_on DRV_HFSPLUS; then
			local outfile="${G_IN_PATH}/BaseSystem.img"
			if [ ! -e "${outfile}" ]; then
				if is_on DEP_DMG2IMG; then
					echo "Converting BaseSystem.dmg to img..."
					if ! $dmg2img "${G_MOUNTP_ESD}/BaseSystem.dmg" "${outfile}" || [ ! -f "${outfile}" ]; then
						rm "${outfile}"
						err_exit "Img conversion failed\n"
					fi
				else
					err_exit "Enable dmg2img to convert to img!\n"
				fi
			fi

			$lyellow; echo "Mapping ${G_NAME_BASE} ($outfile} with qemu..."; $normal
			if [ ! $nbd2_mapped == 1 ]; then
				if ! qemu_map "2" "${outfile}"; then
					err_exit "Error during BaseSystem mapping\n"
				fi
			fi
			G_DEV_BASE="${G_DEV_NBD2}"
		else #DRV_DARLINGDMG
			G_DEV_BASE="${G_MOUNTP_ESD}/BaseSystem.dmg"
		fi


		if is_on DRV_HFSPLUS; then
			# Try to mount ESD
			local part_dev=$(find_first_hfsplus_part "${G_DEV_BASE}")
			if [ -z "${part_dev}" ]; then
				err_exit "Cannot find a valid hfsplus partition in ${G_NAME_BASE}"
			fi
			if ! mount_part "${part_dev}" "${G_NAME_BASE}"; then
				err_exit "Cannot mount ${G_NAME_BASE}\n"
			fi
			G_DEV_ESD="${part_dev}"
		elif ! mount_part "${G_DEV_BASE}" "${G_NAME_BASE}"; then #DRV_DARLINGDMG
			err_exit "Cannot mount ${G_NAME_BASE}\n"
		fi
	fi
	detect_osx_version

	do_system
	do_kernel

	if [ ! "$patchmbr" == "false" ]; then
		docheck_mbr
	fi
	sync

	do_finalize

	sync
	do_cleanup
	$lgreen; echo "All Done!"; $normal
	exit 0
}

function do_finalize(){
	# Install any additional kext
	do_kexts
	# Remove the existing cache, but only if that's not the only usable kernel
	if [ ${G_KEEP_KEXTCACHE} -eq 0 ]; then
		do_remcache
	fi
	# Repair kext permissions
	do_kextperms
	# Install the bootloader
	if is_on BOOT_CHAMELEON; then
		docheck_chameleon
	elif is_on BOOT_CLOVER; then
		docheck_clover
	fi
	# Install the smbios plist if present
	docheck_smbios
	# Install the custom DSDT if present
	docheck_dsdt
}

main "$@"
