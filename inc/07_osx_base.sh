#!/bin/bash
function is_splitted(){
	[ -f "${G_MOUNTP_ESD}/BaseSystem.dmg" ] && return 0
	return 1
}

function detect_osx_version(){
	# Path to the SystemVersion plist
	local verfile
	# MountPoint where the version file is located
	local mountpoint

	# mediamenu -> target
	if [ ${G_MEDIAMENU} -eq 1 ]; then
		mountpoint="${G_NAME_TARGET}"
		$lyellow; echo "Scanning OSX version on ${G_DEV_TARGET}...";$normal
	# splitted -> basesystem
	elif is_splitted; then
		mountpoint="${G_NAME_BASE}"
		$lyellow; echo "Scanning OSX version on BaseSystem..."; $normal
	# dmg/unified
	else
		mountpoint="${G_NAME_ESD}"
		$lyellow; echo "Scanning OSX version on DMG..."; $normal
	fi
	verfile="${G_MOUNTS_DIR}/${mountpoint}/System/Library/CoreServices/SystemVersion.plist"

	if [ ! -f "$verfile" ]; then
		err_exit "Cannot detect OSX Version: ${verfile} is missing!\n"
	fi

	local result=0
	if [ -f "$verfile" ]; then
		G_OSBUILD=$(grep -A1 "<key>ProductBuildVersion</key>" "$verfile" | sed -n 2p | sed 's|[\t <>/]||g;s/string//g')
		G_OSVER=$(grep -A1 "<key>ProductVersion</key>" "$verfile" | sed -n 2p | sed 's|[\t <>/]||g;s/string//g')
		if [[ "${G_OSVER}" =~ "10.6" ]]; then
			G_OSNAME="Snow Leopard"
		elif [[ "${G_OSVER}" =~ "10.7" ]]; then
			G_OSNAME="Lion"
		elif [[ "${G_OSVER}" =~ "10.8" ]]; then
			G_OSNAME="Mountain Lion"
		elif [[ "${G_OSVER}" =~ "10.9" ]]; then
			G_OSNAME="Mavericks"
		elif [[ "${G_OSVER}" =~ "10.10" ]]; then
			G_OSNAME="Yosemite"
		elif [[ "${G_OSVER}" =~ "10.11" ]]; then
			G_OSNAME="El Capitan"
		elif [ ! -z "${G_OSVER}" ] && [ ! -z "${G_OSBUILD}" ]; then
			G_OSNAME="Unsupported"
			G_OSVER="version ($osver)"
			result=1
		else
			G_OSNAME="Unknown"
			G_OSVER="version"
			result=1
		fi
	fi

	if [ ! ${result} -eq 0 ]; then
		err_exit "${G_OSNAME} ${G_OSVER} detected\n"
	else
		$lgreen; echo "${G_OSNAME} ${G_OSVER} detected"; $normal
	fi

	return $result
}

function do_preptarget(){
	if [ ${G_VIRTUALDEV} -eq 1 ]; then #virtual device mode
		if [ -f "${G_DEV_TARGET}" ]; then
			$lred
			if ! read_yn "Image ${G_DEV_TARGET} already exists. Overwrite?"; then
				err_exit ""
			fi
			$normal
		fi
		if [ "${G_DISKFMT}" == "${G_RAW}" ]; then #raw image
			$yellow; echo "Creating Image..."; $normal
			if ! dd if=/dev/zero bs=1 of="${G_DEV_TARGET}" seek="${G_IMAGESIZE}" count=0; then
				err_exit "Error during image creation\n"
			fi

			if [ ! ${G_NBD0_MAPPED} -eq 1 ]; then
				echo "Mapping virtual dev with qemu..."
				if ! qemu_map 0 "${G_DEV_TARGET}"; then
					err_exit "Error during nbd mapping\n"
				fi
				G_DEV_TARGET="${G_DEV_NBD0}"
			fi
		else
			if ! check_command 'qemu-img' == 0; then
				err_exit ""
			fi

			if ! qemu-img create -f "${G_DISKFMT}" "${G_DEV_TARGET}" ${G_IMAGESIZE}; then
				err_exit "Error during Virtual Hard Disk Creation\n"
			fi

			echo "Mapping virtual dev with qemu..."
			qemu-nbd -d ${G_DEV_NBD0} &>/dev/null
			if ! qemu-nbd -c ${G_DEV_NBD0} "${G_DEV_TARGET}"; then
				err_exit "Error during nbd mapping\n"
			fi
			G_DEV_TARGET="${G_DEV_NBD0}"
		fi
	elif [[ ${G_DEV_TARGET} = *[0-9] ]]; then #invalid device
		usage
		err_exit "You must specify the whole device, not a single partition!\n"
	else #block device
		for part in ${G_DEV_TARGET}*[0-9]; do
			echo "Part: $part"
			if grep -q "$part" /proc/mounts; then
				umount "$part"
			fi
			if grep -q "$part" /proc/mounts; then
				err_exit "Couldn't unmount ${part}\n"
			fi
		done
		if ! isRemovable "${G_DEV_TARGET}"; then
			$lred; echo "WARNING, ${G_DEV_TARGET} IS NOT A REMOVABLE DEVICE!"
			echo "ARE YOU SURE OF WHAT YOU ARE DOING?"
			if ! read_yn "Are you REALLY sure you want to continue?"; then
				err_exit "Exiting\n"
			fi
			$normal
		fi

		$lred; echo "WARNING, ALL THE CONTENT OF ${G_DEV_TARGET} WILL BE LOST!"
		if ! read_yn "Are you sure you want to continue?"; then
			err_exit "Exiting\n"
		fi
		$normal
	fi

	if [ ${G_VIRTUALDEV} -eq 1 ]; then
		chmod 666 "${G_DEV_TARGET}"
		chown "$SUDO_USER":"$SUDO_USER" "${G_DEV_TARGET}"
	fi

	local part_scheme
	if is_on PART_MBR; then
		part_scheme="${G_MBR}"
	elif is_on PART_GPT; then
		part_scheme="${G_GPT}"
	else
		err_exit "No partition scheme selected!\n"
	fi

	echo "Creating Partition Table on ${G_DEV_TARGET}..."
	if ! parted -a optimal "${G_DEV_TARGET}" mklabel ${part_scheme}; then
		err_exit "Error during partition table creation\n"
	fi

	if is_on PART_GPT; then
		echo "Creating new ESP on ${G_DEV_TARGET}"
		if ! parted -a optimal "${G_DEV_TARGET}" --script -- mkpart ESP fat32 "1" "100MiB"; then
			err_exit "Error: cannot create new partition\n"
		fi
		echo "Creating new Primary Active Partition on ${G_DEV_TARGET}"
		if ! parted -a optimal "${G_DEV_TARGET}" --script -- mkpart primary hfs+ "100MiB" "-1"; then
			err_exit "Error: cannot create new partition\n"
		fi
	else
		if ! parted -a optimal "${G_DEV_TARGET}" --script -- mkpart primary hfs+ "1" "-1"; then
			err_exit "Error: cannot create new partition\n"
		fi
	fi

	parted -a optimal "${G_DEV_TARGET}" set 1 boot on
	parted -a optimal "${G_DEV_TARGET}" print

	sync

	if [ ${G_VIRTUALDEV} -eq 1 ]; then
		$lyellow; echo "Remapping ${G_OUT_ARG}..."; $normal
		qemu_unmap 0
		qemu_map 0 "${G_OUT_ARG}"
	else
		partprobe "${G_DEV_TARGET}"
	fi

	if is_on PART_GPT; then
		G_DEV_ESP=$(get_part "${G_DEV_TARGET}" 1)
		G_DEV_TARGET=$(get_part "${G_DEV_TARGET}" 2)
	else
		G_DEV_TARGET=$(get_part "${G_DEV_TARGET}" 1)
	fi

	if is_on PART_GPT; then
		$lyellow; echo "Formatting ESP..."; $normal
		if ! mkfs.vfat -F32 "${G_DEV_ESP}"; then
			err_exit "Error during ${G_NAME_ESP} formatting\n"
		fi
		if ! mount_part "${G_DEV_ESP}" "${G_NAME_ESP}"; then
			err_exit "Cannot mount ${G_NAME_ESP}\n"
		fi
	fi

	$lyellow; echo "Formatting partition as HFS+..."; $normal
	if ! mkfs.hfsplus "${G_DEV_TARGET}" -v "smx_installer"; then
		err_exit "Error during ${G_NAME_TARGET} formatting\n"
	fi

	if ! mount_part "${G_DEV_TARGET}" "${G_NAME_TARGET}"; then
		err_exit "Cannot mount ${G_NAME_TARGET}\n"
	fi

	if [ ! -d "${G_MOUNTP_TARGET}/Extra" ]; then
		mkdir ${G_VERBOSE} -p "${G_MOUNTP_TARGET}/Extra"
	fi
}

function copy_progress(){
	local desc="$1"
	local rsync_options="$2"
	local rsync_source="$3"
	local rsync_dest="$4"

	# Number of rsync output lines that will cause a progress update
	local DIALOG_THRES=50

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
		rsync_source="${G_MOUNTP_BASE}/"
	else
		rsync_source="${G_MOUNTP_ESD}/"
	fi

	rsync_flags="-ar ${verbose}"

	if [ ${G_LOG_MODE} -eq 1 ]; then
		$white; echo "Copying Base System to ${G_DEV_TARGET}..."; $normal
		rsync ${rsync_flags} ${rsync_source} ${G_MOUNTP_TARGET}/
	else
		rsync_flags="${rsync_flags} --info=progress2"
		copy_progress "Base System" "${rsync_flags}" "${rsync_source}" "${G_MOUNTP_TARGET}/"
	fi

	if [ -d "${G_MOUNTP_ESD}/Packages" ]; then
		rm ${G_VERBOSE} /mnt/osx/target/System/Installation/Packages
		mkdir ${G_VERBOSE} /mnt/osx/target/System/Installation/Packages

		rsync_source="${G_MOUNTP_ESD}/Packages/"

		if [ ${G_LOG_MODE} -eq 1 ]; then
			$white; echo "Copying installation packages..."; $normal
			rsync ${rsync_flags} ${rsync_source} ${G_MOUNTP_TARGET}/System/Installation/Packages/
		else
			copy_progress "Installation Packages" "${rsync_flags}" "${rsync_source}" "${G_MOUNTP_TARGET}/System/Installation/Packages/"
		fi
		sync
	fi
}

function extract_kernel(){
	$white; echo "Searching in installation packages..."; $normal

	local pkg_file
	local kernel_path
	local osver_minor=$(echo ${G_OSVER} | cut -d '.' -f2)
	local prefix="${G_MOUNTP_TARGET}"

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
		$lyellow; echo "Kernel found in ${pkg_file}"; $normal
		# We can't check md5 here unless we extract, and extraction is slow
		if [ -f "${prefix}/${kernel_path}" ]; then
			$lgreen; echo "Kernel found, copy not needed"; $normal
			result=0
			break
		fi

		local target_path
		local mountpoint
		# For non splitted images (10.6 DVD for instance)
		if ! is_splitted || [ ${G_MEDIAMENU} -eq 1 ]; then
			target_path="/System/Installation"
		fi

		# The system installation packages are in ESD in all cases.
		# The only exception is when we are in mediamenu
		# We have no ESD or BaseSystem mounted, but we may have the installation packages
		# Unless the drive is missing OS X setup files
		if [ ${G_MEDIAMENU} -eq 1 ]; then
			mountpoint="${G_NAME_TARGET}"
		else
			mountpoint="${G_NAME_ESD}"
		fi

		# basename -> full path
		pkg_file="${G_MOUNTS_DIR}/${mountpoint}/${target_path}/Packages/${pkg_file}"
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
		cp -a ${G_VERBOSE} "${dst_path}/${kernel_path}" "${G_MOUNTP_TARGET}/mach_kernel"
	fi
}

function do_kernel(){
	local nkernels
	local kernel
	local path

	local result=1 #error
	local prefix="${G_MOUNTP_TARGET}"

	if [ ${G_MEDIAMENU} -eq 1 ]; then
		extract_kernel
		return
	fi

	local paths="${G_NAME_ESD} ${G_NAME_BASE}"


	local path_pre
	local path_post

	for mountpoint in $paths; do
		$lyellow; echo "Searching for kernels in ${mountpoint}..."; $normal

		# Look for mach_kernel. If it's found and it's not present, copy it
		$white; echo "Searching for mach_kernel..."; $normal
		path_post="/mach_kernel"

		path="${path_pre}/${path_post}"
		if [ -f "${path}" ]; then
			$lgreen; echo "Found mach_kernel in ${mountpoint}"; $normal
			if [ -f "${prefix}/${path_post}" ] && md5_compare "${prefix}/${path_post}" "${path}"; then
				$lgreen; echo "Kernel found, copy not needed"; $normal
			else
				cp -ar ${verbose} "${path}" "${prefix}/${path_post}"
			fi
			result=0
			break
		fi


		# No mach_kernel found. Look for prelinked kernels
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
				if [ -f "${path}/${kernel}" ]; then
					$lgreen; echo "Found prelinkedkernel in ${mountpoint}"; $normal
					if [ -f "${prefix}/${path_post}/${kernel}" ] && md5_compare "${prefix}/${path_post}/${kernel}" "${path}/${kernel}"; then
						$lgreen; echo "Kernel found, copy not needed"; $normal
					else
						cp -ar ${verbose} "${path}/${kernel}" "${prefix}/${path_post}/${kernel}"
					fi
					result=0
					break
				fi
			fi
		fi

		# No prelinked kernel found. Look for kernelcache
		$white; echo "Searching for kernelcaches..."; $normal
		path_post="/System/Library/Caches/com.apple.kext.caches/Startup"

		path="${path_pre}/${path_post}"
		if [ -d "${path}" ]; then
			nkernels=$(ls -1 ${path} | wc -l)	
			if [ $nkernels -gt 0 ]; then
				# Pick the first one, should be "kernelcache"
				kernel=$(ls -1 ${path} | head -n1)
				if [ -f "${path}/${kernel}" ]; then
					$lgreen; echo "Found kernelcache in ${mountpoint}"; $normal
					if [ -f "${prefix}/${path_post}/${kernel}" ] && md5_compare "${prefix}/${path_post}/${kernel}" "${path}/${kernel}"; then
						$lgreen; echo "Kernel found, copy not needed"; $normal
					else
						cp -ar ${verbose} "${path}/${kernel}" "${prefix}/${path_post}/${kernel}"
					fi
					G_KEEP_KEXTCACHE=1
					result=0
					break
				fi
			fi
		fi
	done

	# Nothing found, try installation packages
	if [ ! $result -eq 0 ]; then
		extract_kernel
	fi

	if [ ! $result -eq 0 ]; then
		$lred
		echo "Couldn't find a suitable kernel!"
		echo "Installation WILL NOT BE BOOTABLE"
		$normal
	fi
	return $result	
}