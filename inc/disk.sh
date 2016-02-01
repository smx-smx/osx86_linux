#!/bin/bash
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
