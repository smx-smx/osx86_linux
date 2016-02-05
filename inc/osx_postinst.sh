#!/bin/bash
function do_kexts(){
	local kexts=$(find "$kextdir" -maxdepth 1 -type d -name "*.kext" | wc -l)
	if [ $kexts == 0 ]; then
		$lred; echo "No kext to install"; $normal
	else
		$ylellow; echo "Installing kexts in \"extra_kexts\" directory"; $normal
		kextdir="$scriptdir/extra_kexts"
		for kext in $kextdir/*.kext; do
		echo " Installing $(basename $kext)..."
		cp -R $verbose "$kext" /mnt/osx/target/Extra/Extensions/
		chown -R 0:0 "/mnt/osx/target/Extra/Extensions/$(basename $kext)"
		chmod -R 755 "/mnt/osx/target/Extra/Extensions/$(basename $kext)"
		done
		sync
	fi
}

function docheck_smbios(){
	if [ -f "$scriptdir/smbios.plist" ]; then
		cp $verbose "$scriptdir/smbios.plist" /mnt/osx/target/Extra/smbios.plist
	else
		$lyellow; echo "Skipping smbios.plist, file not found"; $normal
		if [[ ! "$osver" =~ "10.6" ]]; then
			$lred; echo "Warning: proper smbios.plist may be needed"; $normal
		fi
	fi
}

function docheck_dsdt(){
	if [ -f "$scriptdir/DSDT.aml" ]; then
		cp $verbose "$scriptdir/DSDT.aml" /mnt/osx/target/Extra/DSDT.aml
	else
		$lred; echo "DSDT.aml not found!"; $normal
		$lyellow; echo "Using system stock DSDT table"; $normal
	fi
}

function docheck_mbr(){
	if [ -d "$scriptdir/osinstall_mbr" ] &&
		[ -f "$scriptdir/osinstall_mbr/OSInstall.mpkg" ] &&
		[ -f "$scriptdir/osinstall_mbr/OSInstall" ]
		then
			if check_mbrver; then
				do_mbr
			fi
		else
			$lred; echo "Mbr patch files missing!"; $normal
		fi
}

function check_mbrver(){
	if [ -d "$scriptdir/tmp/osinstall_mbr" ]; then rm -r "$scriptdir/tmp/osinstall_mbr"; fi
	echo "Checking patch version..."
	extract_pkg "$scriptdir/osinstall_mbr/OSInstall.mpkg" "$scriptdir/tmp/osinstall_mbr/p"
	if [ -f "/mnt/osx/target/Packages/OSInstall.mpkg" ]; then # esd
		echo "Checking original version..."
		extract_pkg "/mnt/osx/target/Packages/OSInstall.mpkg" "$scriptdir/tmp/osinstall_mbr/o"
	else #target
		echo "Checking original version..."
		extract_pkg "/mnt/osx/target/System/Installation/Packages/OSInstall.mpkg" "$scriptdir/tmp/osinstall_mbr/o"
	fi
	local origver=$(cat "$scriptdir/tmp/osinstall_mbr/o/Distribution" | grep system.version | grep -o 10.* | awk '{print $1}' | sed "s|['\)]||g")
	local origbuild=$(cat "$scriptdir/tmp/osinstall_mbr/o/Distribution" | grep pkg.Essentials | grep -o "version.*" | sed 's/version=//g;s|["/>]||g' | sed "s/'//g")
	local patchver=$(cat "$scriptdir/tmp/osinstall_mbr/p/Distribution" | grep system.version | grep -o 10.* | awk '{print $1}' | sed "s|['\)]||g")
	local patchbuild=$(cat "$scriptdir/tmp/osinstall_mbr/p/Distribution" | grep pkg.Essentials | grep -o "version.*" | sed 's/version=//g;s|["/>]||g' | sed "s/'//g")
	if [ ! "$patchver" == "$origver" ] || [ ! "$patchbuild" == "$origbuild" ]; then
		$lred "WARNING: NOT APPLYING MBR PATCH"
		echo "INCOMPATIBLE VERSIONS"
		$lyellow
		printf "Original:\t$origbuild\nPatch:\t\t$patchbuild\n"
		$normal
		return 1
	else
		return 0
	fi
}

function do_remcache(){
	$lyellow; echo "Deleting Kext Cache..."; $normal
	if [ -f /mnt/osx/target/System/Library/Caches/kernelcache ]; then
		rm /mnt/osx/target/System/Library/Caches/kernelcache
	fi
}

function do_kextperms(){
	$lyellow; echo "Repairing Kext Permissions..."; $normal
	for path in System/Library/Extensions Extra/Extensions; do
		if [ -d /mnt/osx/target/${path} ]; then
			$yellow; echo "/${path}..."; $normal
			find "/mnt/osx/target/${path}" -type d -name "*.kext" -print0 | while read -r -d '' kext; do
				#echo "Fixing ... $kext"
				chmod -R 755 "$kext"
				chown -R 0:0 "$kext"
			done
		fi
	done
	$lgreen; echo "Done"; $normal
}

function do_mbr(){
	$lyellow; echo "Patching Installer to support MBR"; $normal
	cp $verbose "$scriptdir/osinstall_mbr/OSInstall.mpkg" "/mnt/osx/target/System/Installation/Packages/OSInstall.mpkg"
	cp $verbose "$scriptdir/osinstall_mbr/OSInstall" "/mnt/osx/target/System/Library/PrivateFrameworks/Install.framework/Frameworks/OSInstall.framework/Versions/A/OSInstall"
}
