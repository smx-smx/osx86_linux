#!/bin/bash
function detect_osx_version(){
	local verfile
	local mountpoint

	if [ $mediamenu -eq 1 ]; then #look in target
		mountpoint="target"
		$lyellow; echo "Scanning OSX version on $dev...";$normal
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
	if [ $virtualdev -eq 1 ] && [ $vbhdd -eq 0 ]; then
		$yellow; echo "Creating Image..."; $normal
		if [ -f "$dev" ]; then
			$lred; read -p "Image $dev already exists. Overwrite? (y/n)" -n1 -r
			echo; $normal
			if [[ $REPLY =~ ^[Nn]$ ]];then
				err_exit ""
			fi
		fi
		dd if=/dev/zero bs=1 of="$dev" seek="$size" count=0
		if [ ! $? == 0 ]; then
			err_exit "Error during image creation\n"
		fi
	elif [ $virtualdev -eq 1 ] && [ $vbhdd -eq 1 ]; then
			if ! check_command 'vboxmanage' == 0; then
				err_exit ""
			fi
			vboxmanage createhd --filename "$dev" --sizebyte $size --format "$format" --variant Standard
			if [ ! $? == 0 ]; then
				err_exit "Error during Virtual Hard Disk Creation\n"
			fi
	elif [ $virtualdev -eq 0 ] && [ $vbhdd -eq 0 ]; then
		if [[ $dev = *[0-9] ]]; then
			usage
			err_exit "You must specify the whole device, not a single partition!\n"
		fi
		for part in $dev*[0-9]; do
			echo "Part: $part"
			if grep -q "$part" /proc/mounts; then
				umount "$part"
			fi
			if grep -q "$part" /proc/mounts; then
				err_exit "Couldn't unmount "$part"\n"
			fi
		done
		isRO=$(isRO "$dev")
		echo "isRemovable = $isRO"
		if [ $isRO -eq 0 ]; then
			$lred; echo "WARNING, "$dev" IS NOT A REMOVABLE DEVICE!"
			echo "ARE YOU SURE OF WHAT YOU ARE DOING?"
			read -p "Are you REALLY sure you want to continue? (y/n)" -n1 -r
			echo; $normal
			if [[ $REPLY =~ ^[Nn]$ ]];then
				err_exit "Exiting\n"
			fi
		fi

		$lred; echo "WARNING, ALL THE CONTENT OF "$dev" WILL BE LOST!"
		read -p "Are you sure you want to continue? (y/n)" -n1 -r
		echo; $normal
		if [[ $REPLY =~ ^[Nn]$ ]];then
			err_exit "Exiting\n"
		fi
	else
		err_exit "Unknown Operation Mode\n"
	fi

	if [ $virtualdev -eq 1 ]; then
		chmod 666 "$dev"
		chown "$SUDO_USER":"$SUDO_USER" "$dev"
	fi

	if [ $vbhdd -eq 1 ]; then
		echo "Mapping virtual dev with qemu..."
		qemu-nbd -d /dev/nbd0 &>/dev/null
		if ! qemu-nbd -c /dev/nbd0 "$dev"; then
			err_exit "Error during nbd mapping\n"
		fi
	fi

	echo "Creating Partition Table on $dev..."
	if [ $vbhdd -eq 0 ]; then
		parted -a optimal "$dev" mklabel msdos
	else
		parted -a optimal "/dev/nbd0" mklabel msdos
	fi

	if [ ! $? -eq 0 ]; then
		err_exit "Error during partition table creation\n"
	fi

	echo "Creating new Primary Active Partition on $dev"
	if [ $vbhdd -eq 0 ]; then
		parted -a optimal "$dev" --script -- mkpart primary hfs+ "1" "-1"
	else
		parted -a optimal "/dev/nbd0" --script -- mkpart primary hfs+ "1" "-1"
	fi
	if [ ! $? -eq 0 ]; then
		err_exit "Error: cannot create new partition\n"
	fi
	if [ $vbhdd -eq 0 ]; then
		parted -a optimal "$dev" print
		parted -a optimal "$dev" set 1 boot on
	else
		parted -a optimal "/dev/nbd0" print
		parted -a optimal "/dev/nbd0" set 1 boot on
	fi
	sync
	if [ $virtualdev -eq 1 ] && [ $vbhdd -eq 0 ]; then
		if [ ! $nbd0_mapped -eq 1 ]; then
			echo "Mapping virtual dev with qemu..."
			if ! qemu_map "nbd0" "$dev"; then
				err_exit "Error during nbd mapping\n"
			fi
		fi
	fi

	$lyellow; echo "Formatting partition as HFS+"; $normal
	if [ $virtualdev -eq 1 ]; then
		mkfs.hfsplus /dev/nbd0p1 -v "smx_installer"
	else
		mkfs.hfsplus "${dev}1" -v "smx_installer"
	fi
	if [ ! $? -eq 0 ]; then
		err_exit "Error during HFS+ formatting\n"
	fi

	if [ $virtualdev -eq 1 ]; then
		mount_part "/dev/nbd0p1" "target"
	else
		mount_part "${dev}1" "target"
	fi
	if [ ! $? -eq 0 ]; then
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
	rsync_flags="-ar ${verbose} --info=progress2"
	local rsync_size
	$white; echo "Calculating Base System size..."; $normal
	rsync_size=$(du -B1 -sc ${rsync_source}/* | tail -n1 | awk '{print $1}')
	$lyellow; echo "Copying Base System to "$dev"..."; $normal
	dialog --title "osx86_linux" --gauge "Copying base system..." 10 75 < <(
		rsync ${rsync_flags} ${rsync_source} /mnt/osx/target/ | unbuffer -p awk '{print $1}' | sed 's/,//g' | while read doneSz; do
			doneSz=$(trim $doneSz)
			echo $((doneSz * 100 / rsync_size))
		done
	)

	rsync_source="/mnt/osx/esd/Packages/"
	$white; echo "Calculating Installation Packages size..."; $normal
	rsync_size=$(du -B1 -sc ${rsync_source}/* | tail -n1 | awk '{print $1}')

	if [ -d "/mnt/osx/esd/Packages" ]; then
		rm $verbose /mnt/osx/target/System/Installation/Packages
		mkdir $verbose /mnt/osx/target/System/Installation/Packages
		dialog --title "osx86_linux" --gauge "Copying installation packages..." 10 75 < <(
			rsync ${rsync_flags} ${rsync_source} /mnt/osx/target/System/Installation/Packages/ | unbuffer -p awk '{print $1}' | sed 's/,//g' | while read doneSz; do
				doneSz=$(trim $doneSz)
				echo $((doneSz * 100 / rsync_size))
			done
		)
	fi
	sync
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

function do_finalize(){
	do_kexts
	do_remcache
	do_kextperms
	docheck_chameleon
	docheck_smbios
	docheck_dsdt
}
