#!/bin/bash
function do_kexts(){
	local kexts=$(find "${G_KEXTDIR}" -maxdepth 1 -type d -name "*.kext" | wc -l)
	if [ $kexts == 0 ]; then
		$lred; echo "No kext to install"; $normal
	else
		if [ ! -d "${G_MOUNTP_TARGET}/Extra/Extensions" ]; then
			mkdir ${G_VERBOSE} -p "${G_MOUNTP_TARGET}/Extra/Extensions"
		fi
		$lyellow; echo "Installing kexts in \"extra_kexts\" directory"; $normal
		for kext in ${G_KEXTDIR}/*.kext; do
			echo " Installing $(basename $kext)..."
			cp -R ${G_VERBOSE} "$kext" /mnt/osx/target/Extra/Extensions/
			chown -R 0:0 "${G_MOUNTP_TARGET}/Extra/Extensions/$(basename $kext)"
			chmod -R 755 "${G_MOUNTP_TARGET}/Extra/Extensions/$(basename $kext)"
		done
	fi
}

function docheck_smbios(){
	if [ -f "${G_SCRIPTDIR}/smbios.plist" ]; then
		cp ${G_VERBOSE} "${G_SCRIPTDIR}/smbios.plist" "${G_MOUNTP_TARGET}/Extra/smbios.plist"
	else
		$lyellow; echo "Skipping smbios.plist, file not found"; $normal
		$yellow; echo "Warning: proper smbios.plist may be needed"; $normal
	fi
}

function docheck_dsdt(){
	if [ -f "${G_SCRIPTDIR}/DSDT.aml" ]; then
		cp ${G_VERBOSE} "${G_SCRIPTDIR}/DSDT.aml" "${G_MOUNTP_TARGET}/Extra/DSDT.aml"
	else
		$lred; echo "DSDT.aml not found!"; $normal
		$yellow; echo "Using system stock DSDT table"; $normal
	fi
}

function docheck_mbr(){
	if [ -d "${G_SCRIPTDIR}/osinstall_mbr" ] &&
		[ -f "${G_SCRIPTDIR}/osinstall_mbr/OSInstall.mpkg" ] &&
		[ -f "${G_SCRIPTDIR}/osinstall_mbr/OSInstall" ]
		then
			if check_mbrver; then
				do_mbr
			fi
		else
			$lred; echo "Mbr patch files missing!"; $normal
		fi
}

function check_mbrver(){
	if [ -d "${G_TMPDIR}/osinstall_mbr" ]; then
		rm -r "${G_TMPDIR}/osinstall_mbr"
	fi
	echo "Checking patch version..."
	extract_pkg "${G_SCRIPTDIR}/osinstall_mbr/OSInstall.mpkg" "${G_TMPDIR}/osinstall_mbr/p"
	if [ -f "${G_MOUNTP_TARGET}/Packages/OSInstall.mpkg" ]; then # esd
		echo "Checking original version..."
		extract_pkg "${G_MOUNTP_TARGET}/Packages/OSInstall.mpkg" "${G_TMPDIR}/osinstall_mbr/o"
	else #target
		echo "Checking original version..."
		extract_pkg "${G_MOUNTP_TARGET}/System/Installation/Packages/OSInstall.mpkg" "${G_TMPDIR}/osinstall_mbr/o"
	fi
	local origver=$(cat "${G_TMPDIR}/osinstall_mbr/o/Distribution" | grep system.version | grep -o 10.* | awk '{print $1}' | sed "s|['\)]||g")
	local origbuild=$(cat "${G_TMPDIR}/osinstall_mbr/o/Distribution" | grep pkg.Essentials | grep -o "version.*" | sed 's/version=//g;s|["/>]||g' | sed "s/'//g")
	local patchver=$(cat "${G_TMPDIR}/osinstall_mbr/p/Distribution" | grep system.version | grep -o 10.* | awk '{print $1}' | sed "s|['\)]||g")
	local patchbuild=$(cat "${G_TMPDIR}/osinstall_mbr/p/Distribution" | grep pkg.Essentials | grep -o "version.*" | sed 's/version=//g;s|["/>]||g' | sed "s/'//g")
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
	$lyellow; echo "Deleting KernelCache/KextCache..."; $normal
	if [ -f "${G_MOUNTP_TARGET}/System/Library/Caches/kernelcache" ]; then
		rm ${G_VERBOSE} "${G_MOUNTP_TARGET}/System/Library/Caches/kernelcache"
	fi
}

function do_kextperms(){
	$lyellow; echo "Repairing Kext Permissions..."; $normal
	for path in System/Library/Extensions Extra/Extensions; do
		if [ -d "${G_MOUNTP_TARGET}/${path}" ]; then
			$yellow; echo "/${path}..."; $normal
			find "${G_MOUNTP_TARGET}/${path}" -type d -name "*.kext" -print0 | while read -r -d '' kext; do
				#echo "Fixing ... $kext"
				chmod -R 755 "${kext}"
				chown -R 0:0 "${kext}"
			done
		fi
	done
	$lgreen; echo "Done"; $normal
}

function do_mbr(){
	$lyellow; echo "Patching Installer to support MBR"; $normal
	cp ${G_VERBOSE} "${G_SCRIPTDIR}/osinstall_mbr/OSInstall.mpkg" "${G_MOUNTP_TARGET}/System/Installation/Packages/OSInstall.mpkg"
	cp ${G_VERBOSE} "${G_SCRIPTDIR}/osinstall_mbr/OSInstall" "${G_MOUNTP_TARGET}/System/Library/PrivateFrameworks/Install.framework/Frameworks/OSInstall.framework/Versions/A/OSInstall"
}
