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
	if [ "$3" == "silent" ]; then
		mount "$1" -t hfsplus -o rw,force /mnt/osx/$2 &>/dev/null 2>&1
	else
		mount "$1" -t hfsplus -o rw,force /mnt/osx/$2
	fi

	return $?
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
		else
			$lyellow; echo "Restoring volume..."; $normal
			umount /mnt/osx/target
			if [ $virtualdev == 1 ]; then
				fsck.hfsplus -f -y /dev/nbd0p1 || err_exit "fsck failed!\n"
				mount -t hfsplus -o rw,force /dev/nbd0p1 /mnt/osx/target
			else
				fsck.hfsplus -f -y "${src}" || err_exit "fsck failed!\n"
				mount -t hfsplus -o rw,force "${src}" /mnt/osx/target
			fi
			result=$?
		fi
	fi
	return $result
}

function qemu_map(){
	local nbdev=$1
	local image=$2
	qemu-nbd -d /dev/${nbdev} &>/dev/null
	sync
	qemu-nbd -f raw -c /dev/${nbdev} "${image}"
	local result=$?
	if [ $result -eq 0 ]; then
		eval "${nbdev}_mapped=1"
		partprobe /dev/${nbdev}
	fi
	return $result
}
