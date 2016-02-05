#!/bin/bash
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
