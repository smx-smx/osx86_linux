#!/bin/bash
function detect_osx_version(){
	local verfile
	local mountpoint

	if [ $mediamenu -eq 1 ]; then #look in target
		mountpoint="target"
		$lyellow; echo "Scanning OSX version on $dev_target...";$normal
	elif [ -f "/mnt/osx/esd/BaseSystem.dmg" ]; then
		mountpoint="base"
		$lyellow; echo "Scanning OSX version on BaseSystem..."; $normal
	else #look in installer
		mountpoint="esd"
		$lyellow; echo "Scanning OSX version on DMG..."; $normal
	fi
	verfile="/mnt/osx/${mountpoint}/System/Library/CoreServices/SystemVersion.plist" #target

	if [ ! -f "$verfile" ]; then
		err_exit "Cannot detect OSX Version: ${verfile} is missing!\n"
	fi

	local fatal=0
	if [ -f "$verfile" ]; then
		osbuild=$(grep -A1 "<key>ProductBuildVersion</key>" "$verfile" | sed -n 2p | sed 's|[\t <>/]||g;s/string//g')
		osver=$(grep -A1 "<key>ProductVersion</key>" "$verfile" | sed -n 2p | sed 's|[\t <>/]||g;s/string//g')
		if [[ "$osver" =~ "10.6" ]]; then
			osname="Snow Leopard"
		elif [[ "$osver" =~ "10.7" ]]; then
			osname="Lion"
		elif [[ "$osver" =~ "10.8" ]]; then
			osname="Mountain Lion"
		elif [[ "$osver" =~ "10.9" ]]; then
			osname="Mavericks"
		elif [[ "$osver" =~ "10.10" ]]; then
			osname="Yosemite"
		elif [[ "$osver" =~ "10.11" ]]; then
			osname="El Capitan"
		elif [ ! -z "$osver" ] && [ ! -z "$osbuild" ]; then
			osname="Unsupported"
			osver="version ($osver)"
			fatal=1
		else
			osname="Unknown"
			osver="version"
			fatal=1
		fi
	fi

	if [ $fatal -eq 1 ]; then
		err_exit "$osname $osver detected\n"
	else
		$lgreen; echo "$osname $osver detected"; $normal
	fi
}

function do_preptarget(){
	if [ $virtualdev -eq 1 ]; then #virtual device mode
		if [ $vbhdd -eq 0 ]; then #raw image
			$yellow; echo "Creating Image..."; $normal
			if [ -f "$dev_target" ]; then
				$lred; read -p "Image $dev_target already exists. Overwrite? (y/n)" -n1 -r
				echo; $normal
				if [[ $REPLY =~ ^[Nn]$ ]];then
					err_exit ""
				fi
			fi
			if ! dd if=/dev/zero bs=1 of="$dev_target" seek="$size" count=0; then
				err_exit "Error during image creation\n"
			fi
			if [ ! $nbd0_mapped -eq 1 ]; then
				echo "Mapping virtual dev with qemu..."
				if ! qemu_map "nbd0" "$dev_target"; then
					err_exit "Error during nbd mapping\n"
				fi
				dev_target="/dev/nbd0"
			fi
		elif [ $vbhdd -eq 1 ]; then #virtual hdd
			if ! check_command 'vboxmanage' == 0; then
				err_exit ""
			fi

			if ! vboxmanage createhd --filename "${dev_target}" --sizebyte $size --format "$format" --variant Standard; then
				err_exit "Error during Virtual Hard Disk Creation\n"
			fi

			echo "Mapping virtual dev with qemu..."
			qemu-nbd -d /dev/nbd0 &>/dev/null
			if ! qemu-nbd -c /dev/nbd0 "$dev_target"; then
				err_exit "Error during nbd mapping\n"
			fi
			dev_target="/dev/nbd0"
		fi
	elif [[ $dev_target = *[0-9] ]]; then #invalid device
		usage
		err_exit "You must specify the whole device, not a single partition!\n"
	else #block device
		for part in ${dev_target}*[0-9]; do
			echo "Part: $part"
			if grep -q "$part" /proc/mounts; then
				umount "$part"
			fi
			if grep -q "$part" /proc/mounts; then
				err_exit "Couldn't unmount "$part"\n"
			fi
		done
		isRO=$(isRO "$dev_target")
		echo "isRemovable = $isRO"
		if [ $isRO -eq 0 ]; then
			$lred; echo "WARNING, "$dev_target" IS NOT A REMOVABLE DEVICE!"
			echo "ARE YOU SURE OF WHAT YOU ARE DOING?"
			read -p "Are you REALLY sure you want to continue? (y/n)" -n1 -r
			echo; $normal
			if [[ $REPLY =~ ^[Nn]$ ]];then
				err_exit "Exiting\n"
			fi
		fi

		$lred; echo "WARNING, ALL THE CONTENT OF "$dev_target" WILL BE LOST!"
		read -p "Are you sure you want to continue? (y/n)" -n1 -r
		echo; $normal
		if [[ $REPLY =~ ^[Nn]$ ]];then
			err_exit "Exiting\n"
		fi
	fi

	if [ $virtualdev -eq 1 ]; then
		chmod 666 "$dev_target"
		chown "$SUDO_USER":"$SUDO_USER" "$dev_target"
	fi

	local part_scheme
	if is_on PART_MBR; then
		part_scheme="msdos"
	elif is_on PART_GPT; then
		part_scheme="gpt"
	else
		err_exit "No partition scheme selected!\n"
	fi

	echo "Creating Partition Table on $dev_target..."
	if ! parted -a optimal "$dev_target" mklabel ${part_scheme}; then
		err_exit "Error during partition table creation\n"
	fi

	if is_on PART_GPT; then
		echo "Creating new ESP on $dev_target"
		if ! parted -a optimal "$dev_target" --script -- mkpart ESP fat32 "1" "100MiB"; then
			err_exit "Error: cannot create new partition\n"
		fi
		echo "Creating new Primary Active Partition on $dev_target"
		if ! parted -a optimal "$dev_target" --script -- mkpart primary hfs+ "100MiB" "-1"; then
			err_exit "Error: cannot create new partition\n"
		fi
	else
		if ! parted -a optimal "$dev_target" --script -- mkpart primary hfs+ "1" "-1"; then
			err_exit "Error: cannot create new partition\n"
		fi
	fi

	parted -a optimal "$dev_target" set 1 boot on
	parted -a optimal "$dev_target" print

	sync

	if [ $virtualdev -eq 1 ]; then
		if is_on PART_GPT; then
			dev_esp="${dev_target}p1"
			dev_target="${dev_target}p2"
		else
			dev_target="${dev_target}p1"
		fi
	else #virtualdev
		if is_on PART_GPT; then
			dev_esp="${dev_target}1"
			dev_target="${dev_target}2"
		else
			dev_target="${dev_target}1"
		fi
	fi

	if [ $virtualdev -eq 1 ]; then
		$lyellow; echo "Remapping ${out_arg}..."; $normal
		qemu_unmap "nbd0"
		qemu_map "nbd0" "${out_arg}"
	fi

	if is_on PART_GPT; then
		$lyellow; echo "Formatting ESP..."; $normal
		if ! mkfs.vfat -F32 "${dev_esp}"; then
			err_exit "Error during ESP formatting\n"
		fi
		if ! mount_part "${dev_esp}" "esp"; then
			err_exit "Cannot mount ESP\n"
		fi
	fi
	$lyellow; echo "Formatting partition as HFS+..."; $normal
	if ! mkfs.hfsplus "${dev_target}" -v "smx_installer"; then
		err_exit "Error during HFS+ formatting\n"
	fi

	if ! mount_part "${dev_target}" "target"; then
		err_exit "Cannot mount target\n"
	fi

	if [ ! -d /mnt/osx/target/Extra ]; then
		mkdir -p /mnt/osx/target/Extra/Extensions
	fi
}

function do_system(){
	local rsync_flags=""
	local rsync_source
	if [ -f "/mnt/osx/esd/BaseSystem.dmg" ]; then
		rsync_source="/mnt/osx/base/"
	else
		rsync_source="/mnt/osx/esd/"
	fi

	if [ $log_mode -eq 1 ]; then
		rsync_flags="-ar ${verbose}"
		$white; echo "Copying Base System to ${dev_target}..."; $normal
		rsync ${rsync_flags} ${rsync_source} /mnt/osx/target/
	else
		rsync_flags="-ar ${verbose} --info=progress2"
		local rsync_size
		$white; echo "Calculating Base System size..."; $normal
		rsync_size=$(du -B1 -sc ${rsync_source}/* | tail -n1 | awk '{print $1}')
		$white; echo "Copying Base System to ${dev_target}..."; $normal
		dialog --title "osx86_linux" --gauge "Copying base system..." 10 75 < <(
			rsync ${rsync_flags} ${rsync_source} /mnt/osx/target/ | unbuffer -p awk '{print $1}' | sed 's/,//g' | while read doneSz; do
				doneSz=$(trim $doneSz)
				echo $((doneSz * 100 / rsync_size))
			done
		)
	fi

	if [ -d "/mnt/osx/esd/Packages" ]; then
		rm $verbose /mnt/osx/target/System/Installation/Packages
		mkdir $verbose /mnt/osx/target/System/Installation/Packages

		rsync_source="/mnt/osx/esd/Packages/"
		if [ $log_mode -eq 1 ]; then
			$white; echo "Copying installation packages..."; $normal
			rsync ${rsync_flags} ${rsync_source} /mnt/osx/target/System/Installation/Packages/
		else
			$white; echo "Calculating Installation Packages size..."; $normal
			rsync_size=$(du -B1 -sc ${rsync_source}/* | tail -n1 | awk '{print $1}')
			dialog --title "osx86_linux" --gauge "Copying installation packages..." 10 75 < <(
				rsync ${rsync_flags} ${rsync_source} /mnt/osx/target/System/Installation/Packages/ | unbuffer -p awk '{print $1}' | sed 's/,//g' | while read doneSz; do
					doneSz=$(trim $doneSz)
					echo $((doneSz * 100 / rsync_size))
				done
			)
		fi
		sync
	fi
}

function do_kernel(){
	# Source of kernel files
	mountpoint=$1
	$yellow; echo "Copying kernel..."; $normal
	local kernel_cache_path="System/Library/Caches/com.apple.kext.caches/Startup/kernelcache"
	local osver_minor=$(echo $osver | cut -d '.' -f2)
	# Mavericks and above
	if [ $osver_minor -ge 9 ]; then
		$lyellow; echo "Kernel is in BaseSystemBinaries.pkg, extracting..."; $normal
		local esd_path
		if [ ! "$mountpoint" == "esd" ]; then
			target_path="System/Installation"
		fi
		extract_pkg "/mnt/osx/${mountpoint}/${target_path}/Packages/BaseSystemBinaries.pkg" "${scriptdir}/tmp/bsb" "skip"
		if [ $osver_minor -eq 9 ]; then
			cp -a $verbose "${scriptdir}/tmp/bsb/mach_kernel" "/mnt/osx/target/"
		else
			cp -a $verbose "${scriptdir}/tmp/bsb/${kernel_cache_path}" "/mnt/osx/target/${kernel_cache_path}"
		fi
	# This won't work from mediamenu and < 10.10 (esd not mounted there)
	elif [ -f "/mnt/osx/esd/mach_kernel" ]; then
		cp -av /mnt/osx/esd/mach_kernel /mnt/osx/target/
	fi
	if [ ! -f "/mnt/osx/target/mach_kernel" ] && [ ! -f "/mnt/osx/target/${kernel_cache_path}" ]; then
		$lred; echo "WARNING! Kernel installation failed!!"
		echo "Media will likely be unbootable!"; $normal
	fi
}
