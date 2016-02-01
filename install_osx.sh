#!/bin/bash
rev=$(git log --pretty=oneline 2>/dev/null | wc -l)
if [ $rev -gt 0 ]; then
	program_revision="git r$rev"
else
	program_revision="git"
fi

if [ -z $really_verbose ]; then
	really_verbose=0
elif [ $really_verbose -eq 1 ]; then
	verbose="-v"
else
	verbose=""
fi

trap err_exit SIGINT

workdir=$(pwd -P)
scriptdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd -P)"
cd $scriptdir

for i in $scriptdir/inc/*.sh; do
	source "$i"
done

function mediamenu(){
	mediamenu=1
	if [ $virtualdev == 1 ]; then
		if [ $nbd0_mapped -eq 0 ]; then
			$white; echo "Mapping ${in_arg}..."; $normal
			if ! qemu_map "nbd0" "$in_arg"; then
				err_exit "Can't map ${in_arg}\n"
			fi
			dev_target="/dev/nbd0"
		fi
		if [ ! -b "/dev/nbd0p1" ]; then
			err_exit "Corrupted image\n"
		fi
	fi

	if [ $virtualdev -eq 1 ]; then
		dev_target="${dev_target}p1"
	else
		dev_target="${dev_target}1"
	fi

	if ! grep -q "/mnt/osx/target" /proc/mounts; then
		$yellow; echo "Mounting..."; $normal
		if ! mount_part "$dev_target" "target" "silent"; then
			err_exit "Cannot mount target\n"
		else
			$lgreen; echo "Target Mounted"; $normal
		fi
		if [ ! -d /mnt/osx/target/Extra ]; then
			mkdir -p /mnt/osx/target/Extra/Extensions
		fi
		detect_osx_version
	fi
	echo "Working on ${dev_target}"
	echo "Choose an operation..."
	echo "1  - Manage kexts"
	echo "2  - Manage chameleon Modules"
	echo "3  - Manage kernels"
	echo "4  - Reinstall / Update chameleon"
	echo "5  - Reinstall stock kernel"
	echo "6  - Install / Reinstall MBR Patch"
	echo "7  - Install / Reinstall Custom DSDT"
	echo "8  - Install / Reinstall SMBios"
	echo "9  - Erase Setup"
	echo "10 - Delete Kext Cache"
	echo "11 - Tweaks Menu"
	echo "0  - Exit"
	$white; printf "Choose an option: "; read choice; $normal
	case "$choice" in
		0)
			err_exit ""
			;;
		1)
			clear
			kextmenu
			mediamenu
			;;
		2)
			clear
			chammodmenu
			mediamenu
			;;
		3)
			clear
			kernelmenu
			mediamenu
			;;
		4)
			docheck_chameleon
			mediamenu
			;;
		5)
			do_kernel "target"
			mediamenu
			;;
		6)
			docheck_mbr
			pause; clear
			mediamenu
			;;
		7)
			docheck_dsdt
			pause; clear
			mediamenu
			;;
		8)
			docheck_smbios
			pause; clear
			mediamenu
			;;
		9)
			do_cleanup
			if [ $virtualdev == 1 ]; then
				$lred; echo "WARNING: You are about to delete ${in_arg} content!"
				read -p "Are you really sure you want to continue? (y/n)" -n1 -r
				echo; $normal
				if [[ $REPLY =~ ^[Nn]$ ]];then
					err_exit ""
				fi
				rm "${in_arg}"
				$lgreen; echo "$(basename $in_arg) succesfully deleted" ; $normal
				#else
				#	echo "Can't delete image"
			else
				$lred; echo "WARNING: You are about to erase ${dev_target}!"
				read -p "Are you really sure you want to continue? (y/n)" -n1 -r
				echo; $normal
				if [[ $REPLY =~ ^[Nn]$ ]];then
					err_exit ""
				fi
					dd if=/dev/zero of="${dev_target}" bs=512 count=1
					$lgreen: echo echo "${dev_target} succesfully erased"; $normal
			fi
			err_exit ""
			;;
		10)
			do_remcache
			mediamenu
			;;
		11)
			clear
			tweakmenu
			mediamenu
			;;
		*)
			pause "Invalid option, press [enter] to try again"
			clear
			mediamenu
	esac
}

function tweakmenu(){
	local tweaks=($(find "$scriptdir/tweaks" -maxdepth 1 -type f -name "*.sh"))
	if [ ${#tweaks[@]} -eq 0 ]; then
		$lred; echo "No tweak to install"; $normal
		pause "Press [enter] to return to menu"
		mediamenu
	fi
	printf "Choose a tweak to apply: "
	$white; echo "0 - Return to main menu"; $normal

	for i in ${!tweaks[@]}; do
		local name=$(grep tweakname= ${tweaks[$i]} | grep -o "=.*" | sed 's|[="]||g')
		echo $((i + 1)) - ${name}
	done
	$white; echo "Choose a tweak to apply"; $normal
	read choice
	if [ -z $choice ] || [ $choice -lt 0 ] || [ $choice -gt ${#tweaks[@]} ]; then
		pause "Invalid option, press [enter] to try again"
		clear
		tweakmenu
	elif [ $choice -eq 0 ]; then
		clear
		mediamenu
	else
		clear
		local tweak=${tweaks[$((choice-1))]}
		$yellow; echo "Applying ${tweak}..."; $normal
		bash "${tweak}"
	fi
	$lgreen; echo "Done!"; $normal
	tweakmenu
}

function kextmenu(){
	kexts=$(find "$kextdir" -maxdepth 1 -type d -name "*.kext" | wc -l)
	if [ $kexts == 0 ]; then
		$lred; echo "No kext to install"; $normal
		pause "Press [enter] to return to menu"
		mediamenu
	fi
	printf "Choose a kext to Install / Reinstall: "
	local k
	local eskdir=$(echo "$kextdir" | sed 's/\ /\\\//g;s/\//\\\//g')
	$white; echo "0 - Return to main menu"; $normal
	for k in `seq $kexts`; do
		local option=$(find "$kextdir" -maxdepth 1 -type d -not -name ".gitignore" -name "*.kext" | sed "s/$eskdir\///g" | sed -n "$k"p)
			eval kext$k="$option"
			if [ -d "/mnt/osx/target/Extra/Extensions/"$option"" ]; then
				printf "[*]\t$k - $option\n"
			else
				printf "[ ]\t$k - $option\n"
			fi
	done
	$white; echo "Choose a kext to install/uninstall"; $normal
	read choice
	local name="kext$choice"
	if [ "$choice" == "0" ]; then
		clear
		mediamenu
	fi
	if [ -z "${!name}" ]; then
		pause "Invalid option, press [enter] to try again"
		clear
		kextmenu
	else
	clear
		if [ -d "/mnt/osx/target/Extra/Extensions/${!name}" ]; then
			$yellow; echo "Removing ${!name}..."; $normal
			rm -R "/mnt/osx/target/Extra/Extensions/${!name}"
		else
			$yellow; echo "Installing ${!name}..."; $normal
			cp -R "$kextdir/${!name}" /mnt/osx/target/Extra/Extensions/
			chown -R 0:0 "/mnt/osx/target/Extra/Extensions/${!name}"
			chmod -R 755 "/mnt/osx/target/Extra/Extensions/${!name}"
		fi
	fi
	$lgreen; echo "Done!"; $normal
	kextmenu
}

function chammodmenu(){
	modules=$(find "$scriptdir/chameleon/Modules" -maxdepth 1 -type f -name "*.dylib" | wc -l)
	if [ $modules == 0 ]; then
		$lred; echo "No module to install"; $normal
		pause "Press [enter] to return to menu"
		mediamenu
	fi
	printf "Choose a module to Install / Reinstall: "
	local m
	local esmdir=$(echo "$scriptdir/chameleon/Modules" | sed 's/\ /\\\//g;s/\//\\\//g')
	$white; echo "0 - Return to main menu"; $normal
	for m in `seq $modules`; do
		local option=$(find "$scriptdir/chameleon/Modules" -maxdepth 1 -type f -not -name ".gitignore" -name "*.dylib" | sed "s/$esmdir\///g" | sed -n "$m"p)
			eval module$m="$option"
			if [ -f "/mnt/osx/target/Extra/Modules/"$option"" ]; then
				printf "[*]\t$m - $option\n"
			else
				printf "[ ]\t$m - $option\n"
			fi
	done
	$white; echo "Choose a module to install/uninstall"; $normal
	read choice
	local name="module$choice"
	if [ "$choice" == "0" ]; then
		clear
		mediamenu
	fi
	if [ -z "${!name}" ]; then
		pause "Invalid option, press [enter] to try again"
		clear
		chammodmenu
	else
	clear
		if [ -f "/mnt/osx/target/Extra/Modules/${!name}" ]; then
			$yellow; echo "Removing ${!name}..."; $normal
			rm "/mnt/osx/target/Extra/Modules/${!name}"
		else
			$yellow; echo "Installing ${!name}..."; $normal
			cp "$scriptdir/chameleon/Modules/${!name}" /mnt/osx/target/Extra/Modules/
			chmod -R 755 "/mnt/osx/target/Extra/Modules/${!name}"
		fi
	fi
	$lgreen; echo "Done!"; $normal
	chammodmenu
}

function kernelmenu(){
	kernels=$(find "$kerndir" -maxdepth 1 -type f -not -name ".gitignore" | wc -l)
	if [ $kernels == 0 ]; then
		$lred; echo "No kernel to install"; $normal
		pause "Press [enter] to return to menu"
		mediamenu
	fi
	printf "Choose a kernel to Install / Reinstall: "
	local k
	local eskdir=$(echo "$kerndir" | sed 's/\ /\\\//g;s/\//\\\//g')
	$white; echo "0 - Return to main menu"; $normal
	for k in `seq $kernels`; do
		local option=$(find "$kerndir" -maxdepth 1 -type f -not -name ".gitignore" | sed "s/$eskdir\///g" | sed -n "$k"p)
			eval kern$k="$option"
			if [ -f "/mnt/osx/target/"$option"" ]; then
				printf "[*]\t$k - $option\n"
			else
				printf "[ ]\t$k - $option\n"
			fi
	done
	$white; echo "Choose a kernel to install/uninstall"; $normal
	read choice
	local name="kern$choice"
	if [ "$choice" == "0" ]; then
		clear
		mediamenu
	fi
	if [ -z "${!name}" ]; then
		pause "Invalid option, press [enter] to try again"
		clear
		kernelmenu
	else
	clear
		if [ -f "/mnt/osx/target/${!name}" ]; then
			if [ "${!name}" == "mach_kernel" ]; then #stock kernel
				read -p "Warning, you are about to overwrite the default Kernel. Do you want to back it up to \"apple_kernel\"? (yes/no/abort)" -n1 -r
				echo
				if [[ $REPLY =~ ^[Aa]$ ]];then
					kernelmenu
				elif [[ $REPLY =~ ^[Yy]$ ]];then
					$yellow; echo "Backing up mach_kernel..."; $normal
					mv /mnt/osx/target/mach_kernel /mnt/osx/target/apple_kernel
					$yellow; echo "Copying new mach_kernel..."; $normal
					cp $verbose "$kerndir/${!name}" /mnt/osx/target/
					chmod 755 "/mnt/osx/target/${!name}"
				fi
			else #alternative kernel name, we can delete
				$yellow; echo "Removing ${!name}..."; $normal
				rm $verbose "/mnt/osx/target/${!name}"
			fi
		else
			$yellow; echo "Installing ${!name}..."; $normal
			cp $verbose "$kerndir/${!name}" /mnt/osx/target/
			chmod 755 "/mnt/osx/target/${!name}"
		fi
	fi
	$lgreen; echo "Done!"; $normal
	kernelmenu
}

function vdev_check(){
	echo "Virtual HDD Image Mode"
	virtualdev=1
	if ! check_command 'qemu-nbd' == 0; then
		err_exit ""
	fi

 	# which partition holds the image
	local file_info
	if [ -f "$1" ]; then
		file_info=$(df -TP "$1")
	else
		touch "$1"
		file_info=$(df -TP "$1")
		rm "$1"
	fi
	local fstype=$(echo "${file_info}" | awk '/^\/dev/ {print $2}')
	local mountdev=$(echo "${file_info}" | awk '/^\/dev/ {print $1}')
	if [ ! -b "${mountdev}" ]; then
		err_exit "${mountdev} is not a valid block device\n"
	fi
	local isRO=$(isRO "${mountdev}"; echo $?)
	if [ $isRO -eq 1 ]; then
		err_exit "${mountdev} is mounted in R/O mode!\n"
	fi
	if [ "${fstype}" == "ntfs" ] && [ "${fstype}" == "fuseblk" ]; then
		$lred; echo "WARNING, YOUR DMG IS STORED ON A FUSE FILESYSTEM!, READ/WRITE OPERATIONS MAY BE SLOW"
		echo "A non-FUSE FS is recommended"
		read -p "Are you sure you want to continue? (y/n)" -n1 -r
		echo; $normal
		if [[ $REPLY =~ ^[Nn]$ ]];then
			err_exit ""
		fi
	fi
	if [ ! -f "$1" ] && [ "$out_ext" == ".vdi" ]; then
		vbhdd=1; format=VDI
	elif [ ! -f "$1" ] && [ "$out_ext" == ".vhd" ]; then
		vbhdd=1; format=VHD
	elif [ ! -f "$1" ] && [ "$out_ext" == ".vmdk" ]; then
		vbhdd=1; format=VMDK
	elif [ -f "$in_arg" ] && [ -z "$out_arg" ]; then
		dev_target="${in_arg}"
		clear; mediamenu
		#err_exit "$1 already exists. Exiting\n"
	#else
	#	err_exit "Unknown Error!\n"
	fi
	if [ -z $size ]; then
		if [ $mkrecusb -eq 1 ]; then
			size=$((400 * 1024 * 1024)) #400
		else
			size=$((10 * 1024 * 1024 * 1024)) #10gb
		fi
	fi
	check_space "$mountdev" "$size" 1
	isdev=$(echo "$1" | grep -q "/dev/"; echo $?)
	if [ $isdev == 0 ]; then
		err_exit "Something wrong, not going to erase ${dev_target}\n"
	fi
}

function do_kexts(){
	local kexts=$(find "$kextdir" -maxdepth 1 -type d -name "*.kext" | wc -l)
	if [ $kexts == 0 ]; then
		$lred; echo "No kext to install"; $normal
	else
		$ylellow; echo "Installing kexts in \"extra_kexts\" directory"; $normal
		kextdir="$scriptdir/extra_kexts"
		for kext in $kextdir/*.kext; do
		echo " Installing $(basename $kext)..."
		cp -R $verbose "$kext" /mnt/osx/target/Extra/Extensions/
		chown -R 0:0 "/mnt/osx/target/Extra/Extensions/$(basename $kext)"
		chmod -R 755 "/mnt/osx/target/Extra/Extensions/$(basename $kext)"
		done
		sync
	fi
}

function docheck_smbios(){
	if [ -f "$scriptdir/smbios.plist" ]; then
		cp $verbose "$scriptdir/smbios.plist" /mnt/osx/target/Extra/smbios.plist
	else
		$lyellow; echo "Skipping smbios.plist, file not found"; $normal
		if [[ ! "$osver" =~ "10.6" ]]; then
			$lred; echo "Warning: proper smbios.plist may be needed"; $normal
		fi
	fi
}

function docheck_dsdt(){
	if [ -f "$scriptdir/DSDT.aml" ]; then
		cp $verbose "$scriptdir/DSDT.aml" /mnt/osx/target/Extra/DSDT.aml
	else
		$lred; echo "DSDT.aml not found!"; $normal
		$lyellow; echo "Using system stock DSDT table"; $normal
	fi
}

function docheck_chameleon(){
	if  [ -f  "$scriptdir/chameleon/boot1h" ] && [ -f  "$scriptdir/chameleon/boot" ]; then
		do_chameleon
	else
		$lred; echo "WARNING: Cannot install Chameleon, critical files missing"
		echo "Your installation won't be bootable"; $normal
	fi
}

function docheck_mbr(){
	if [ -d "$scriptdir/osinstall_mbr" ] &&
		[ -f "$scriptdir/osinstall_mbr/OSInstall.mpkg" ] &&
		[ -f "$scriptdir/osinstall_mbr/OSInstall" ]
		then
			if check_mbrver; then
				do_mbr
			fi
		else
			$lred; echo "Mbr patch files missing!"; $normal
		fi
}

function check_mbrver(){
	if [ -d "$scriptdir/tmp/osinstall_mbr" ]; then rm -r "$scriptdir/tmp/osinstall_mbr"; fi
	echo "Checking patch version..."
	extract_pkg "$scriptdir/osinstall_mbr/OSInstall.mpkg" "$scriptdir/tmp/osinstall_mbr/p"
	if [ -f "/mnt/osx/target/Packages/OSInstall.mpkg" ]; then # esd
		echo "Checking original version..."
		extract_pkg "/mnt/osx/target/Packages/OSInstall.mpkg" "$scriptdir/tmp/osinstall_mbr/o"
	else #target
		echo "Checking original version..."
		extract_pkg "/mnt/osx/target/System/Installation/Packages/OSInstall.mpkg" "$scriptdir/tmp/osinstall_mbr/o"
	fi
	local origver=$(cat "$scriptdir/tmp/osinstall_mbr/o/Distribution" | grep system.version | grep -o 10.* | awk '{print $1}' | sed "s|['\)]||g")
	local origbuild=$(cat "$scriptdir/tmp/osinstall_mbr/o/Distribution" | grep pkg.Essentials | grep -o "version.*" | sed 's/version=//g;s|["/>]||g' | sed "s/'//g")
	local patchver=$(cat "$scriptdir/tmp/osinstall_mbr/p/Distribution" | grep system.version | grep -o 10.* | awk '{print $1}' | sed "s|['\)]||g")
	local patchbuild=$(cat "$scriptdir/tmp/osinstall_mbr/p/Distribution" | grep pkg.Essentials | grep -o "version.*" | sed 's/version=//g;s|["/>]||g' | sed "s/'//g")
	if [ ! "$patchver" == "$origver" ] || [ ! "$patchbuild" == "$origbuild" ]; then
		$lred "WARNING: NOT APPLYING MBR PATCH"
		echo "INCOMPATIBLE VERSIONS"
		$lyellow
		printf "Original:\t$origbuild\nPatch:\t\t$patchbuild\n"
		$normal
		return 1
	else
		return 0
	fi
}

function do_remcache(){
	$lyellow; echo "Deleting Kext Cache..."; $normal
	if [ -f /mnt/osx/target/System/Library/Caches/kernelcache ]; then
		rm /mnt/osx/target/System/Library/Caches/kernelcache
	fi
}

function do_kextperms(){
	$lyellow; echo "Repairing Kext Permissions..."; $normal
	for path in System/Library/Extensions Extra/Extensions; do
		if [ -d /mnt/osx/target/${path} ]; then
			$yellow; echo "/${path}..."; $normal
			find "/mnt/osx/target/${path}" -type d -name "*.kext" -print0 | while read -r -d '' kext; do
				#echo "Fixing ... $kext"
				chmod -R 755 "$kext"
				chown -R 0:0 "$kext"
			done
		fi
	done
	$lgreen; echo "Done"; $normal
}

function do_mbr(){
	$lyellow; echo "Patching Installer to support MBR"; $normal
	cp $verbose "$scriptdir/osinstall_mbr/OSInstall.mpkg" "/mnt/osx/target/System/Installation/Packages/OSInstall.mpkg"
	cp $verbose "$scriptdir/osinstall_mbr/OSInstall" "/mnt/osx/target/System/Library/PrivateFrameworks/Install.framework/Frameworks/OSInstall.framework/Versions/A/OSInstall"
}

function do_clover(){
	local target_mbr
	local target_pbr
	if [ $virtualdev -eq 1 ]; then
		target_mbr="/dev/nbd0"
		target_pbr="${target_mbr}p1"
	else
		target_mbr="${dev}"
		target_pbr="${dev}1"
	fi

	$lyellow; echo "Installing clover..."; $normal
	if [ -f "${scriptdir}/clover/boot0ss" ]; then
		$yellow; echo "Flashing Master boot record..."; $normal
		dd if="${scriptdir}/clover/boot0ss" of="${target_mbr}"
	fi
	if [ -f "${scriptdir}/clover/boot1f32alt" ]; then
		$yellow; echo "Flashing Partition boot record..."; $normal
		dd if="${target_pbr}" count=1 bs=512 of="${scriptdir}/tmp/origbs"
		cp $verbose "${scriptdir}/clover/boot1f32alt" "${scriptdir}/tmp/newbs"
		dd if="${scriptdir}/tmp/origbs" of="${scriptdir}/tmp/newbs" skip=3 seek=3 bs=1 count=87 conv=notrunc
		dd if="${scriptdir}/tmp/newbs" of="${target_pbr}" bs=512 count=1
	fi
}

function do_chameleon(){
	$lyellow; echo "Installing chameleon..."; $normal
	cp $verbose "$scriptdir/chameleon/boot" /mnt/osx/target/
	sync

	if [ -d "$scriptdir/chameleon/Themes" ]; then
		$yellow; echo "Copying Themes..."; $normal
		cp -R "$scriptdir/chameleon/Themes" "/mnt/osx/target/Extra/"
	fi
	if [ -d "$scriptdir/chameleon/Modules" ]; then
		$yellow; echo "Copying Modules..."; $normal
		cp -R "$scriptdir/chameleon/Modules" "/mnt/osx/target/Extra/"
	fi
	sync

	$yellow; echo "Flashing boot record..."; $normal
	if [ ! -f  "$scriptdir/chameleon/boot0" ]; then
		$lred; echo "WARNING: MBR BootCode (boot0) Missing."
		echo "Installing Chameleon on Partition Only"; $normal
	else
		local do_instMBR=0
		if [ -z $chameleonmbr ]; then
			read -p "Do you want to install Chameleon on MBR? (y/n)" -n1 -r
			echo
			if [[ $REPLY =~ ^[Yy]$ ]]; then do_instMBR=1; fi
		elif [ "$chameleonmbr" == "true" ]; then do_instMBR=1; fi
	fi
	if [ $virtualdev -eq 1 ]; then
		if [ $do_instMBR -eq 1 ]; then
			dd bs=446 count=1 conv=notrunc if="$scriptdir/chameleon/boot0" of="/dev/nbd0"
			sync
		fi
		dd if="$scriptdir/chameleon/boot1h" of="/dev/nbd0p1"
		sync
	else
		if [ $do_instMBR -eq 1 ]; then
			dd bs=446 count=1 conv=notrunc if="$scriptdir/chameleon/boot0" of="$dev"
		fi
		dd if="$scriptdir/chameleon/boot1h" of="${dev}1"
	fi
	sync
}

function check_space {
	local device=$1
	local minimum=$2
	local strict=$3
	freespace=$(( $(df "$device" | sed -n 2p | awk '{print $4}') * 1024))
	printf "FreeSpace:\t$freespace\n"; printf "Needed:\t\t$minumum\n"
	if [ $freespace -ge $minimum ]; then
		return 0
	else
		if [ $strict -eq 1 ]; then
			err_exit "Not enough free space\n"
		else
			return 1
		fi
	fi
}

function check_commands {
	$lyellow; echo "Checking Commands..."
	$normal
	#if [ $commands_checked == 1 ]; then
		#add checks for other commands after the initial check
	#	echo &>/dev/null
	#else
		commands=('dialog' 'grep' 'tput' 'dd' 'sed' 'parted' 'awk' 'mkfs.hfsplus' 'wget' 'dirname' 'basename' 'parted' 'pidof' 'gunzip' 'bunzip2' 'cpio')
	#fi
	for command in "${commands[@]}"; do
		if ! check_command $command == 0; then
			$normal
			err_exit ""
		fi
		$normal
	done
}

function find_cmd {
	# Command to look for
	cmdvar=$1
	# Preferred search dir
	cmd_dir=$2
	# Full command name (optional)
	cmd=$3

	local cmd_path
	if [ ! -z "${cmd}" ]; then
		cmd_path="${cmd_dir}/${cmd}"
	elif [ ! -z "${cmd_dir}" ]; then
		cmd_path="${cmd_dir}/${cmdvar}"
	else
		cmd_path="$(type -P "${cmdvar}")"
	fi

	# Store the command path in the command-named variable (ex xar -> $xar)
	if [ -e "${cmd_path}" ]; then
		eval ${cmdvar}=${cmd_path}
	else
		unset ${cmdvar}
	fi

	#echo "Arg   --> $cmd"
	#echo "Var   --> ${cmd}"
	#echo "Value --> ${!cmd}"
}

function check_command {
	local command=$1
	echo $command | grep -q '\$'
	if [ $? == 0 ]; then
		command_name=$(echo $command | sed -e 's/\$//g')
		command=${!command_name}
	else
		command_name=$command
	fi

	type -P "$command" &>/dev/null
	local cmdstat=$?

	if [ -z "$command" ]; then
		cmdstat=1
	fi
	$lcyan; printf "$command_name: "
	if [ $cmdstat == 0 ]; then
		$lgreen; printf "Found\n"; $normal
		return 0
	elif [ $cmdstat == 1 ]; then
		$lred; printf "Not Found\n"; $normal
		return 1
	else
		$lightgray; printf "Unknown Error\n"; $normal
		return 2
	fi
}

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
		for mountpoint in base esd target; do
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

	# Export APIs for tweaks
	export -f do_remcache
	export -f do_kextperms
	export -f docheck_smbios
	export -f docheck_dsdt
	export -f docheck_mbr
	export -f mount_part
	export -f check_commands
	mediamenu=0

	if [ -z $SUDO_USER ]; then
		export SUDO_USER="root"
	fi

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

	name=$(basename "$1" 2>/dev/null) #input
	in_ext=".${name##*.}"
	in_name="${name%.*}"

	name=$(basename "$2") #output
	out_ext=".${name##*.}"
	out_name="${name%.*}"
	unset name

	load_config

	if is_on DEP_XAR; then
		find_cmd "xar" "${scriptdir}/bins/bin"
		docheck_xar
	fi
	if is_on DEP_DMG2IMG; then
		find_cmd "dmg2img" "${scriptdir}/bins/bin"
		docheck_dmg2img
	fi
	if is_on DEP_PBZX; then
		find_cmd "pbzx" "${scriptdir}"
		docheck_pbzx
	fi
	if is_on DEP_KCONFIG; then
		find_cmd "kconfig_mconf" "${scriptdir}/bins/bin" "kconfig-mconf"
		docheck_kconfig
	fi
	if is_on DEP_DARLING_DMG; then
		find_cmd "mount_hfs" "${scriptdir}/bins/bin" "darling-dmg"
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
	# Create ESD mountpoint
	if [ ! -d /mnt/osx/esd ]; then mkdir /mnt/osx/esd; fi
	# Create BaseSystem mountpoint
	if [ ! -d /mnt/osx/base ]; then mkdir /mnt/osx/base; fi
	# Create target mountpoint
	if [ ! -d /mnt/osx/target ]; then mkdir /mnt/osx/target; fi

	nbd0_mapped=0
	nbd1_mapped=0
	nbd2_mapped=0


	do_init_qemu

	dev_esd=""
	dev_base=""
	dev_target=""
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

	if [ -z $commands_checked ]; then	commands_checked=0; fi
	if [ $commands_checked == 0 ]; then
		check_commands	#Check all required commands exist
		commands_checked=1
		export commands_checked
	fi
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

	if [ -f "/mnt/osx/esd/BaseSystem.dmg" ]; then
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
	do_kernel "esd"

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

main "$@"
