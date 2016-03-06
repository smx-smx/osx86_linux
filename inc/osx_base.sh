#!/bin/bash
function is_splitted(){
	[ -f "/mnt/osx/esd/BaseSystem.dmg" ] && return 0
	return 1
}

function detect_osx_version(){
	# Path to the SystemVersion plist
	local verfile
	# MountPoint where the version file is located
	local mountpoint

	# mediamenu -> target
	if [ $mediamenu -eq 1 ]; then
		mountpoint="target"
		$lyellow; echo "Scanning OSX version on $dev_target...";$normal
	# splitted -> basesystem
	elif is_splitted; then
		mountpoint="base"
		$lyellow; echo "Scanning OSX version on BaseSystem..."; $normal
	# dmg/unified
	else
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
				$lred
				if ! read_yn "Image $dev_target already exists. Overwrite?"; then
					err_exit ""
				fi
				$normal
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
		if ! isRemovable "${dev_target}"; then
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

function copy_progress(){
	local desc="$1"
	local rsync_options="$2"
	local rsync_source="$3"
	local rsync_dest="$4"

	local rsync_size
	$white; echo "Calculating ${desc} size..."; $normal
	rsync_size=$(du -b --apparent-size -sc ${rsync_source}/* | tail -n1 | awk '{print $1}')
	$white; echo "Copying ${desc} to ${rsync_dest}..."; $normal


	dialog --title "osx86_linux" --gauge "Copying ${desc}..." 10 75 < <(
		local lines=0
		rsync ${rsync_flags} ${rsync_source} ${rsync_dest} | unbuffer -p awk '{print $1}' | while read -r line; do
			# Don't count empty lines
			if [ ! -z "$line" ]; then
				lines=$(($lines + 1))
				# If rsync was refreshed enough times, update progress
				if [ $lines -gt $DIALOG_THRES ]; then
					# Remove nasty characters (trim), and remove the numeric separator
					local doneSz=$(trim $(echo $line | sed 's/,//g'))
					echo $(($doneSz * 100 / $rsync_size))
					lines=0
				fi
			fi
		done
	)
}

function do_system(){
	local rsync_flags=""
	local rsync_source
	if is_splitted; then
		rsync_source="/mnt/osx/base/"
	else
		rsync_source="/mnt/osx/esd/"
	fi

	local DIALOG_THRES=50

	if [ $log_mode -eq 1 ]; then
		rsync_flags="-ar ${verbose}"
		$white; echo "Copying Base System to ${dev_target}..."; $normal
		rsync ${rsync_flags} ${rsync_source} /mnt/osx/target/
	else
		rsync_flags="-ar ${verbose} --info=progress2"
		copy_progress "Base System" "${rsync_flags}" "${rsync_source}" "/mnt/osx/target/"
	fi

	if [ -d "/mnt/osx/esd/Packages" ]; then
		rm $verbose /mnt/osx/target/System/Installation/Packages
		mkdir $verbose /mnt/osx/target/System/Installation/Packages

		rsync_source="/mnt/osx/esd/Packages/"

		if [ $log_mode -eq 1 ]; then
			$white; echo "Copying installation packages..."; $normal
			rsync ${rsync_flags} ${rsync_source} /mnt/osx/target/System/Installation/Packages/
		else
			copy_progress "Installation Packages" "${rsync_flags}" "${rsync_source}" "/mnt/osx/target/System/Installation/Packages/"
		fi
		sync
	fi
}

function do_kernel(){
	local nkernels
	local kernel
	local path

	local result=1 #error
	local prefix="/mnt/osx/target"

	local paths="target"
	if [ $mediamenu -eq 0 ]; then
		paths="esd base ${paths}"
	fi


	local path_pre
	local path_post

	for mountpoint in $paths; do
		$lyellow; echo "Searching for kernels in ${mountpoint}..."; $normal

		$white; echo "Searching for prelinkedkernels..."; $normal
		path_pre="/mnt/osx/${mountpoint}"
		path_post="/System/Library/PrelinkedKernels"

		path="${path_pre}/${path_post}"
		if [ -d "${path}" ]; then
			# How many kernels are there?
			nkernels=$(ls -1 ${path} | wc -l)
			if [ $nkernels -gt 0 ]; then
				# Pick the first one, should be "prelinkedkernel"
				kernel=$(ls -1 ${path} | head -n1)
				if [ -f "${path}/${kernel}" ] && [ ! -f "${prefix}/${path_post}/${kernel}" ]; then
					$lgreen; echo "Found prelinkedkernel in ${mountpoint}"; $normal
					cp -ar ${verbose} "${path}/${kernel}" "${prefix}/${path_post}/${kernel}"
					result=0
					break
				fi
			fi
		fi

		$white; echo "Searching for kernelcaches..."; $normal
		path_post="/System/Library/Caches/com.apple.kext.caches/Startup"

		path="${path_pre}/${path_post}"
		if [ -d "${path}" ]; then
			nkernels=$(ls -1 ${path} | wc -l)	
			if [ $nkernels -gt 0 ]; then
				# Pick the first one, should be "kernelcache"
				kernel=$(ls -1 ${path} | head -n1)
				if [ -f "${path}/${kernel}" ] && [ ! -f "${prefix}/${path_post}/${kernel}" ]; then
					$lgreen; echo "Found kernelcache in ${mountpoint}"; $normal
					cp -ar ${verbose} "${path}/${kernel}" "${prefix}/${path_post}/${kernel}"
					result=0
					break
				fi
			fi
		fi

		$white; echo "Searching for mach_kernel..."; $normal
		path_post="/mach_kernel"

		path="${path_pre}/${path_post}"
		if [ -f "${path}" ] && [ ! -f "${prefix}/${path_post}" ]; then
			$lgreen; echo "Found mach_kernel in ${mountpoint}"; $normal
			cp -ar ${verbose} "${path}" "${prefix}/${path_post}"
			result=0
			break
		fi

	done

	$white; echo "Searching in installation packages..."; $normal

	# Attempt pkg extraction
	if [ ! $result -eq 0 ]; then
		local pkg_file
		local kernel_path
		local osver_minor=$(echo $osver | cut -d '.' -f2)

		case $osver_minor in
			# TODO: Not sure about 10
			9-10)
				pkg_file="BaseSystemBinaries.pkg"
				# Relative to the package
				kernel_path="/mach_kernel"
				;;
			11)
				pkg_file="Essentials.pkg"
				# Relative to the package
				kernel_path="/System/Library/Kernels/kernel"
				;;
			*)
				;;
		esac

		if [ ! -z "${pkg_file}" ]; then
			$lyellow; echo "Kernel found in ${pkg_file}, extracting..."; $normal

			local target_path
			local mountpoint
			# For non splitted images (10.6 DVD for instance)
			if ! is_splitted || [ $mediamenu -eq 1 ]; then
				target_path="/System/Installation"
			fi

			# The system installation packages are in ESD in all cases.
			# The only exception is when we are in mediamenu
			# We have no ESD or BaseSystem mounted, but we may have the installation packages
			# Unless the drive is missing OS X setup files
			if [ $mediamenu -eq 1 ]; then
				mountpoint="target"
			else
				mountpoint="esd"
			fi

			# basename -> full path
			pkg_file="/mnt/osx/${mountpoint}/${target_path}/Packages/${pkg_file}"
			if [ ! -f "${pkg_file}" ]; then
				err_exit "Cannot continue, missing package ${pkg_file}\n"
			fi

			# Extract to tmp without the extension
			local dst_path="${scriptdir}/tmp/$(basename ${pkg_file%.*})"
			# TODO: Fix CPIO filter
			#if ! extract_pkg "${pkg_file}" "${dst_path}" "${kernel_path}"; then
			if ! extract_pkg "${pkg_file}" "${dst_path}" ""; then
				err_exit "${pkg_file} exraction FAILED!\n"
			fi

			# Extracted kernel -> target
			cp -a $verbose "${dst_path}/${kernel_path}" "/mnt/osx/target/mach_kernel"
		fi
	fi

	if [ ! $result -eq 0 ]; then
		$lred
		echo "Couldn't find a suitable kernel!"
		echo "Installation WILL NOT BE BOOTABLE"
		$normal
	fi
	return $result	
}