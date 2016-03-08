#!/bin/bash
function isRO(){
	local mountdev="$1"
	#if it's a link, follow it
	if [ -L "${mountdev}" ]; then
		mountdev=$(readlink -f "${mountdev}")
	fi
	local dev_major=$((0x$(stat -c "%t" "${mountdev}")))
	local dev_minor=$((0x$(stat -c "%T" "${mountdev}")))
	if [ ! -f "/sys/dev/block/${dev_major}:${dev_minor}/ro" ]; then
		err_exit "Can't get readonly flag\n"
	fi
	local isRO=$(cat /sys/dev/block/${dev_major}:${dev_minor}/ro)
	return $((${isRO} ^ 1))
}

function isRemovable(){
	local mountdev="$1"
	#if it's a link, follow it
	if [ -L "${mountdev}" ]; then
		mountdev=$(readlink -f "${mountdev}")
	fi
	local dev_major=$((0x$(stat -c "%t" "${mountdev}")))
	local dev_minor=$((0x$(stat -c "%T" "${mountdev}")))
	if [ ! -f "/sys/dev/block/${dev_major}:${dev_minor}/removable" ]; then
		err_exit "Can't get removable flag\n"
	fi
	local isRemovable=$(cat /sys/dev/block/${dev_major}:${dev_minor}/removable)
	return $((${isRemovable} ^ 1))
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
	if isRO "${mountdev}"; then
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

function qemu_umount_all(){
	local result=0
	grep "/dev/nbd" /proc/mounts | awk '{print $1}' | while read mountpoint; do
		$lyellow; echo "Unmounting "${mountpoint}"..."; $normal
		if ! umount ${mountpoint}; then
			$lred; echo "Can't unmount "$mount""; $normal
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
		while [ ! -b /dev/nbd0 ]; do
			: #nop
		done
		if [ ! -b /dev/nbd0 ]; then
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
	if [ ! -b /dev/nbd0 ]; then
		err_exit "Cannot load qemu nbd kernel module\n"
	fi
}

function domount_part(){
	local src="$1"
	local type="$2"
	local flags="$3"

	local result

	local mount_flags_pre="-t hfsplus"
	local mount_flags_post="/mnt/osx/${type}"
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
		$mount_hfs "$src" ${mount_flags_post}
		result=$?
	else
		err_exit "Cannot mount ${src}. Driver not selected\n"
	fi

	return $result
}

function mount_part(){
	local src=$1
	local type=$2
	local flags=$3

	if grep -q "$src" /proc/mounts; then
		return 0
	fi

	domount_part "$src" "$type" "$flags"
	local result=$?

	if [ "$type" == "target" ]; then
		if touch /mnt/osx/target/check_ro; then
			rm /mnt/osx/target/check_ro
		elif [ -b "${src}" ]; then
			$lyellow; echo "Recovering volume..."; $normal
			umount /mnt/osx/target
			fsck.hfsplus -f -y "${src}" || err_exit "fsck failed!\n"
			mount -t hfsplus -o rw,force "${src}" /mnt/osx/target || err_exit "mount failed!\n"
		fi
	fi
	return $result
}

function qemu_map(){
	local nbdev=$1
	local image=$2
	local result
	qemu_unmap "${nbdev}"
	local chk_var="${nbdev}_mapped"
	if [ ! ${!chk_var} -eq 0 ]; then
		result=1
		return $result
	fi
	local qemu_args
	if [ $vbhdd -eq 0 ]; then
		qemu_args="-f raw"
	fi
	qemu-nbd ${qemu_args} -c /dev/${nbdev} "${image}"
	result=$?
	if [ $result -eq 0 ]; then
		eval "${nbdev}_mapped=1"
		sleep 0.1
	fi
	return $result
}

function qemu_unmap(){
	local nbdev=$1
	qemu-nbd -d /dev/${nbdev} &>/dev/null
	sync
	eval "${nbdev}_mapped=0"
}
