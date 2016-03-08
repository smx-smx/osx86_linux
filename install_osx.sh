#!/bin/bash
rev=$(git log --pretty=oneline 2>/dev/null | wc -l)
if [ $rev -gt 0 ]; then
	program_revision="git r$rev"
else
	program_revision="git"
fi

verbose=""
if [ -z $log_mode ]; then
	log_mode=0
fi
if [ -z $really_verbose ]; then
	really_verbose=0
elif [ $really_verbose -eq 1 ]; then
	verbose="-v"
fi

trap err_exit SIGINT

workdir=$(pwd -P)
scriptdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd -P)"
cd $scriptdir

for i in $scriptdir/inc/*.sh; do
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
	if [ ! "${scriptdir}/tmp" == "/tmp" ] && [ -d "${scriptdir}/tmp" ]; then
		rm -r "${scriptdir}/tmp"
	fi

	local result=0
	if [ -d /mnt/osx ]; then
		for mountpoint in esp base esd target; do
			while grep -q "$mountpoint" /proc/mounts; do
				$yellow; echo "umount /mnt/osx/${mountpoint}"; $normal
				if ! umount "/mnt/osx/${mountpoint}"; then
					sleep 1
				fi
				result=$?
			done
			if [ -d "/mnt/osx/${mountpoint}" ] && isEmpty "/mnt/osx/${mountpoint}"; then
				rmdir "/mnt/osx/${mountpoint}"
			else
				result=1
			fi
		done

		if isEmpty "/mnt/osx"; then
			rmdir /mnt/osx
		else
			$lyellow; echo "Some partitions couldn't be unmounted. Check what's accessing them and unmount them manually"; $normal
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

	echo "Version: $program_revision"

	if [ -z $SUDO_USER ]; then
		export SUDO_USER="root"
	fi

	export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:${scriptdir}/bins/lib

	check_commands	#check that all required commands exist
	find_cmd "xar" "${scriptdir}/bins/bin"
	find_cmd "dmg2img" "${scriptdir}/bins/bin"
	find_cmd "pbzx" "${scriptdir}/bins/bin"
	find_cmd "kconfig_mconf" "${scriptdir}/bins/bin" "kconfig-mconf"
	find_cmd "mount_hfs" "${scriptdir}/bins/bin" "darling-dmg"

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

	in_arg="$1"
	out_arg="$2"

	local name=$(basename "$1" 2>/dev/null) #input
	in_ext=".${name##*.}"
	in_name="${name%.*}"

	name=$(basename "$2") #output
	out_ext=".${name##*.}"
	out_name="${name%.*}"
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

	if [ "$in_ext" == ".pkg" ] || [ "$in_ext" == ".mpkg" ]; then #./install_osx.sh [file.pkg/mpkg]
		if [ -z "$out_arg" ]; then #no dest dir
			usage
			err_exit "Invalid Destination Folder\n"
		fi
		extract_pkg "$in_arg" "$out_arg"
		do_cleanup
		exit 0
	fi

	kextdir="${scriptdir}/extra_kexts"
	kerndir="${scriptdir}/kernels"
	filepath="$( cd "$( dirname "$in_arg" 2>/dev/null)" && pwd -P)"
	devpath="$( cd "$( dirname "$out_arg" 2>/dev/null)" && pwd -P)"

	do_cleanup || exit 1

	# Create working dir
	if [ ! -d /mnt/osx ]; then mkdir -p /mnt/osx; fi
	# Create ESP mountpoint
	if [ ! -d /mnt/osx/esp ]; then mkdir /mnt/osx/esp; fi
	# Create ESD mountpoint
	if [ ! -d /mnt/osx/esd ]; then mkdir /mnt/osx/esd; fi
	# Create BaseSystem mountpoint
	if [ ! -d /mnt/osx/base ]; then mkdir /mnt/osx/base; fi
	# Create target mountpoint
	if [ ! -d /mnt/osx/target ]; then mkdir /mnt/osx/target; fi

	nbd0_mapped=0
	nbd1_mapped=0
	nbd2_mapped=0
	mediamenu=0

	do_init_qemu

	dev_esd=""
	dev_base=""
	dev_target=""
	dev_esp=""
	size=$3 #for img creation

	virtualdev=0
	vbhdd=0

	if [[ ! "$OSTYPE" == linux* ]]; then
		err_exit "This script can only be run under Linux\n"
	fi

	if [ ! ${EUID} -eq 0 ]; then
	   err_exit "This script must be run as root\n"
	fi

	mkrecusb=0
	if [ -b "$in_arg" ] &&
		[ ! -f "$in_arg" ] &&
		[ ! -d "$in_arg" ] &&
		[ -z "$out_arg" ] &&
		[ -z "$3" ]
	then #./install_osx.sh [dev]
		dev_target="$in_arg"
		mediamenu
	elif [ -f "$in_arg" ] && [ -z "$out_arg" ] && [ -z "$3" ]; then #./install_osx.sh [file]
		if [ "$in_ext" == ".dmg" ]; then #./install_osx.sh [file.dmg]
			usage
			err_exit "You must specify a valid target drive or image\n"
		elif [ "$in_ext" == ".img" ] ||
			[ "$in_ext" == ".hdd" ] ||
			[ "$in_ext" == ".vhd" ] ||
			[ "$in_ext" == ".vdi" ] ||
			[ "$in_ext" == ".vmdk" ]
		then #./install_osx.sh [file.img]
			virtualdev=1
			mediamenu
		fi
	elif [ ! -b "$in_arg" ] &&
		[ ! -f "$in_arg" ] &&
		[ ! -d "$in_arg" ] &&
		[ -z "$out_arg" ] &&
		[ -z "$3" ]
	then
		err_exit "No such device\n"
	fi

	if [ ! "$in_ext" == ".dmg" ] && [ ! "$in_ext" == ".img" ]; then
			if [ "$1" == "--mkchameleon" ]; then
				mkrecusb=1
			else
				usage
				err_exit "Invalid file specified\n"
			fi
	fi

	if [ -z "$out_arg" ]; then
		usage
		err_exit "You must specify a valid target drive or image\n"
	fi

	if [ ! -b "$out_arg" ]; then
		if [ "$out_ext" == ".img" ] ||
			[ "$out_ext" == ".hdd" ] ||
			[ "$out_ext" == ".vhd" ] ||
			[ "$out_ext" == ".vdi" ] ||
			[ "$out_ext" == ".vmdk" ]
		then
			vdev_check "$out_arg" #switch to Virtual HDD mode & check
		fi
	fi

	dev_target="$out_arg"

	if [[ $in_arg == "/dev/sr[0-9]" ]]; then
		$lgreen; echo "CD Source Device Detected"; $normal
		if [ -z "$out_arg" ]; then
			err_exit "You must specify a valid destination to create an img file\n"
		elif [ -f "$out_arg" ]; then
			err_exit "$out_arg already exists\n"
		else
			$yellow; echo "Image creation is in progress..."
			echo "The process may take some time"; $normal
			if [ ! -d "$(dirname "$out_arg")" ] && ! mkdir -p "$(dirname "$out_arg")"; then
				err_exit "Can't create destination folder\n"
			fi
			dd if="$in_arg" of="$out_arg"
			watch -n 10 kill -USR1 `pidof dd`
		fi
	fi

	do_preptarget
	if [ $mkrecusb -eq 1 ]; then
		do_finalize
		err_exit ""
	fi

	if is_on DRV_HFSPLUS; then
		if is_on DEP_DMG2IMG; then
			outfile="${filepath}/${in_name}.img"
			if [ ! -e "${outfile}" ]; then
				echo "Converting ${in_arg} to img..."
				if ! $dmg2img "${in_arg}" "${outfile}" || [ ! -f "${outfile}" ]; then
					rm "$outfile"
					err_exit "Img conversion failed\n"
				fi
			fi
		fi

		$lyellow; echo "Mapping esd ($outfile) with qemu..."; $normal
		if [ ! $nbd1_mapped == 1 ]; then
			if ! qemu_map "nbd1" "${outfile}"; then
				err_exit "Error during image mapping\n"
			fi
		fi
		dev_esd="/dev/nbd1"
	else #DRV_HFSPLUS
		dev_esd="${in_arg}" #Take the esd as is (darling-dmg)
	fi

	$yellow; echo "Mounting Partitions..."; $normal

	if is_on DRV_HFSPLUS; then
		for partition in 2 3; do
				if mount_part "${dev_esd}p${partition}" "esd"; then
					dev_esd="${dev_esd}p${partition}"
					break
				fi
		done
		if [ "${dev_esd}" == "/dev/nbd1" ]; then
			err_exit "Cannot mount esd\n"
		fi
	elif ! mount_part "${dev_esd}" "esd"; then #DRV_HFSPLUS
		err_exit "Cannot mount esd\n"
	fi

	if is_splitted; then
		if is_on DRV_HFSPLUS; then
			if is_on DEP_DMG2IMG; then
				outfile="${filepath}/BaseSystem.img"
				if [ ! -e "${outfile}" ]; then
					echo "Converting BaseSystem.dmg..."
					if ! $dmg2img "/mnt/osx/esd/BaseSystem.dmg" "${outfile}" || [ ! -f "${outfile}" ]; then
						rm "$outfile"
						err_exit "Img conversion failed\n"
					fi
				fi
			fi

			$lyellow; echo "Mapping BaseSystem ($outfile} with qemu..."; $normal
			if [ ! $nbd2_mapped == 1 ]; then
				if ! qemu_map "nbd2" "${outfile}"; then
					err_exit "Error during BaseSystem mapping\n"
				fi
			fi
			dev_base="/dev/nbd2"
		else #DRV_HFSPLUS
			dev_base="/mnt/osx/esd/BaseSystem.dmg"
		fi

		if is_on DRV_HFSPLUS; then
			for partition in 2 3; do
					if mount_part "${dev_base}p${partition}" "base"; then
						dev_base="${dev_esd}p${partition}"
						break
					fi
			done
			if [ "${dev_base}" == "/dev/nbd2" ]; then
				err_exit "Cannot mount basesystem\n"
			fi
		elif ! mount_part "${dev_base}" "base"; then
			err_exit "Cannot mount basesystem\n"
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
	if [ $virtualdev == 1 ] && [ "$out_ext" == ".img" ] || [ "$out_ext" == ".hdd" ]; then
		read -p "Do you want to convert virtual image to a VDI file? (y/n)" -n1 -r
		echo
		if [[ $REPLY =~ ^[Yy]$ ]];then
			if ! vboxmanage convertdd  "${out_arg}" "${devpath}/${out_name}.vdi" || [ ! -f "${devpath}/${out_name}.vdi" ]; then
				err_exit "Conversion Failed\n"
			else
				chmod 666 "$devpath/$dfilename".vdi
				chown "$SUDO_USER":"$SUDO_USER" "$devpath/$dfilename".vdi
				read -p "Do you want to delete the img file? (y/n)" -n1 -r
				echo
				if [[ $REPLY =~ ^[Yy]$ ]];then
					rm "${out_arg}"
				fi
			fi
		fi
	fi
	exit 0
}

function do_finalize(){
	# Install any additional kext
	do_kexts
	# Remove the existing caches
	do_remcache
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
