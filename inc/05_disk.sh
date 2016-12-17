#!/bin/bash
function isRO(){
	local dev="$1"
	#if it's a link, follow it
	dev=$(readlink -f "${dev}")

	local dev_major=$((0x$(stat -c "%t" "${dev}")))
	local dev_minor=$((0x$(stat -c "%T" "${dev}")))
	if [ ! -f "/sys/dev/block/${dev_major}:${dev_minor}/ro" ]; then
		err_exit "Can't get readonly flag\n"
	fi
	local isRO=$(cat /sys/dev/block/${dev_major}:${dev_minor}/ro)
	return $((${isRO} ^ 1))
}

function isRemovable(){
	local dev="$1"
	#if it's a link, follow it
	dev=$(readlink -f "${dev}")

	local dev_major=$((0x$(stat -c "%t" "${dev}")))
	local dev_minor=$((0x$(stat -c "%T" "${dev}")))
	if [ ! -f "/sys/dev/block/${dev_major}:${dev_minor}/removable" ]; then
		err_exit "Can't get removable flag\n"
	fi
	local isRemovable=$(cat "/sys/dev/block/${dev_major}:${dev_minor}/removable")
	return $((${isRemovable} ^ 1))
}

function isVirtual(){
	local dev="$1"
	#if it's a link, follow it
	dev=$(readlink -f "${dev}")

	local dev_major=$((0x$(stat -c "%t" "${dev}")))
	local dev_minor=$((0x$(stat -c "%T" "${dev}")))

	if [ ! -d "/sys/dev/block/${dev_major}:${dev_minor}" ]; then
		err_exit "Cannot find device in sysfs!\n"
	fi

	local devNode=$(readlink -f "/sys/dev/block/${dev_major}:${dev_minor}")
	if str_contains "${devNode}" "/virtual/block/"; then
		return 0
	fi
	return 1
}

function get_part(){
	err_exit "Temporarly removed"
}

function vdev_check(){
	echo "Virtual HDD Image Mode"
	G_VIRTUALDEV=1
	if ! check_command 'qemu-nbd' == 0; then
		err_exit ""
	fi

 	# which partition holds the image
	local file_info
	if [ -f "${G_OUT_ARG}" ]; then
		file_info=$(df -TP "${G_OUT_ARG}")
	else
		touch "${G_OUT_ARG}"
		file_info=$(df -TP "${G_OUT_ARG}")
		rm "${G_OUT_ARG}"
	fi

	local fstype=$(echo "${file_info}" | awk '/^\/dev/ {print $2}')
	local mountdev=$(echo "${file_info}" | awk '/^\/dev/ {print $1}')
	if [ ! -b "${mountdev}" ]; then
		err_exit "${mountdev} is not a valid block device\n"
	fi
	if isRO "${mountdev}"; then
		err_exit "${mountdev} is mounted in R/O mode!\n"
	fi
	if [ "${fstype}" == "ntfs" ] || [ "${fstype}" == "fuseblk" ]; then
		$lred; echo "WARNING, YOUR DMG IS STORED ON A NTFS/FUSE FILESYSTEM!, READ/WRITE OPERATIONS MAY BE SLOW"
		echo "A non-FUSE FS is recommended"
		if ! read_yn "Are you sure you want to continue?"; then
			err_exit ""
		fi
	fi
	if [ -f "${G_OUT_ARG}" ] && [ -f "${G_IN_ARG}" ] && [ -z "${G_OUT_ARG}" ]; then
		G_DEV_TARGET="${G_IN_ARG}"
		clear
		mediamenu
	fi
	if [ -z ${G_IMAGESIZE} ]; then
		if [ ${G_MKRESCUEUSB} -eq 1 ]; then
			G_IMAGESIZE=$((400 * 1024 * 1024)) #400 mb
		else
			G_IMAGESIZE=$((10 * 1024 * 1024 * 1024)) #10 gb
		fi
	fi
	check_space "${mountdev}" 1
	local isdev=$(echo "${G_OUT_ARG}" | grep -q "/dev/"; echo $?)
	if [ $isdev == 0 ]; then
		err_exit "Something wrong, not going to erase ${G_DEV_TARGET}\n"
	fi
}

function check_space() {
	local device=$1
	local strict=$3
	local freespace=$(( $(df "$device" | sed -n 2p | awk '{print $4}') * 1024))
	printf "FreeSpace:\t$freespace\n"
	printf "Needed:\t\t%d\n" ${G_IMAGESIZE}
	if [ $freespace -ge ${G_IMAGESIZE} ]; then
		return 0
	elif [ $strict -eq 1 ]; then
		err_exit "Not enough free space\n"
	else
		return 1
	fi
}

function qemu_umount_all(){
	local result=0
	grep "/dev/nbd" /proc/mounts | awk '{print $1}' | while read mountpoint; do
		$lyellow; echo "Unmounting ${mountpoint}..."; $normal
		if ! umount "${mountpoint}"; then
			$lred; echo "Can't unmount ${mount}"; $normal
			result=1
		fi
	done
	return $result
}

function qemu_unmap_all(){
	for device in /dev/nbd*; do
		if [ -b "${device}" ]; then
			qemu-nbd -d "${device}" &>/dev/null
		fi
	done
}

function do_init_qemu(){
	echo "Setting qemu-nbd dev..."
	if [ ! -b /dev/nbd0 ]; then
		modprobe nbd max_part=10
		$lyellow; echo "Waiting for nbd to be fully loaded"; $normal
		while [ ! -b "${G_DEV_NBD0}" ]; do
			: #nop
		done
		if [ ! -b "${G_DEV_NBD0}" ]; then
			err_exit "Error while loading module \"nbd\"\n"
		fi
	else
		echo "Reloading nbd..."
		echo "Checking for mounts..."
		if grep -q "/dev/nbd" /proc/mounts; then
			if ! qemu_umount_all; then
				err_exit ""
			fi
			qemu_unmap_all
		fi
		rmmod nbd
		modprobe nbd max_part=10
	fi
	if [ ! -b "${G_DEV_NBD0}" ]; then
		err_exit "Cannot load qemu nbd kernel module\n"
	fi
}

function domount_part(){
	local src="$1"
	local type="$2"
	local flags="$3"

	local result

	local mount_flags_pre="-t hfsplus"
	local mount_flags_post="${G_MOUNTS_DIR}/${type}"
	if [ "$flags" == "silent" ]; then
		mount_flags_post="${mount_flags_post} &>/dev/null 2>&1"
	fi

	if is_on DRV_HFSPLUS || [ "$type" == "target" ]; then
		case $type in
			esd|base)
				mount_flags_pre="${mount_flags_pre} -o ro"
				;;
			esp)
				mount_flags_pre="-t vfat"
				;;
			*)
				mount_flags_pre="${mount_flags_pre} -o rw,force"
				;;
		esac
		eval mount ${mount_flags_pre} "${src}" ${mount_flags_post}
		result=$?
	elif is_on DRV_DARLING; then
		$mount_hfs "${src}" ${mount_flags_post}
		result=$?
	else
		err_exit "Cannot mount ${src}. Driver not selected\n"
	fi

	return $result
}

function find_first_hfsplus_part(){
	local device="$1"
	
	local partno=1	
	local part_dev
	while(true); do
		part_dev=$(get_part "${device}" ${partno})
		if [ -z "${part_dev}" ]; then
			return 1
		fi

		local part_type=$(blkid "${part_dev}" -s TYPE -o value)
		if [ ! -z "${part_type}" ] && [ "${part_type}" == "hfsplus" ]; then
			echo "${part_dev}"
			return 0
		fi

		partno=$((${partno} + 1))
	done
	return 1
}

function mount_part(){
	local src=$1
	local type=$2
	local flags=$3

	if grep -q "${src}" /proc/mounts; then
		return 0
	fi

	domount_part "${src}" "${type}" "${flags}"
	local result=$?

	# Check if we can actually write to the target
	if [ "$type" == "target" ]; then
		if touch "${G_MOUNTP_TARGET}/check_ro"; then
			rm "${G_MOUNTP_TARGET}/check_ro"
		# We can't, and it's a valid block device
		elif [ -b "${src}" ]; then
			$lyellow; echo "Recovering volume..."; $normal
			umount "${G_MOUNTP_TARGET}"
			fsck.hfsplus -f -y "${src}" || err_exit "fsck failed!\n"
			mount -t hfsplus -o rw,force "${src}" /mnt/osx/target || err_exit "mount failed!\n"
		fi
	fi
	return $result
}

function qemu_map(){
	local nbd_devno=$1
	local image=$2
	local result
	qemu_unmap "${nbd_devno}"
	
	local chk_var="G_NBD${nbd_devno}_MAPPED"
	if [ ! ${!chk_var} -eq 0 ]; then
		result=1
		return $result
	fi
	local nbd_devp="G_DEV_NBD${nbd_devno}"
	local qemu_args="-f ${G_DISKFMT}"
	qemu-nbd ${qemu_args} -c "${!nbd_devp}" "${image}"
	result=$?
	if [ $result -eq 0 ]; then
		eval "G_NBD${nbd_dev}_MAPPED=1"
		sleep 0.1
	fi
	return $result
}

function qemu_unmap(){
	local nbd_devno=$1
	qemu-nbd -d "/dev/nbd${nbd_devno}" &>/dev/null
	sync
	eval "G_NBD${nbd_dev}_MAPPED=0"
}
