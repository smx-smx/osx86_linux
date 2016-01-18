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
