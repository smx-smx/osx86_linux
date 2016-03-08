#!/bin/bash
function docheck_chameleon(){
	if is_on PART_GPT; then
		$lred; echo "Cannot install chameleon on GPT drives!"; $normal
	elif [ -f  "${G_CHAMELEONDIR}/boot0" ] &&
		[ -f  "${G_CHAMELEONDIR}/boot1h" ] &&
		[ -f  "${G_CHAMELEONDIR}/boot" ]
	then
		do_chameleon
	else
		$lred
		echo "WARNING: Cannot install Chameleon, critical files missing"
		echo "Your installation won't be bootable"
		$normal
	fi
}

function do_chameleon(){
	$lyellow; echo "Installing chameleon..."; $normal
	cp ${G_VERBOSE} "${G_CHAMELEONDIR}/boot" /mnt/osx/target/
	sync

	if [ -d "${G_CHAMELEONDIR}/Themes" ]; then
		$yellow; echo "Copying Themes..."; $normal
		cp ${G_VERBOSE} -R "${G_CHAMELEONDIR}/Themes" "${G_MOUNTP_TARGET}/Extra/"
	fi
	if [ -d "${G_CHAMELEONDIR}/Modules" ]; then
		$yellow; echo "Copying Modules..."; $normal
		cp ${G_VERBOSE} -R "${G_CHAMELEONDIR}/Modules" "${G_MOUNTP_TARGET}/Extra/"
	fi
	sync

	if [ ! -f  "${G_CHAMELEONDIR}/boot0" ]; then
		$lred; echo "WARNING: MBR BootCode (boot0) Missing."
		echo "Installing Chameleon on Partition Only"; $normal
	else
		if read_yn "Do you want to install Chameleon on MBR?"; then
			$white; echo "Writing MBR boot code..."; $normal
			dd bs=446 count=1 conv=notrunc if="${G_CHAMELEONDIR}/boot0" of="${G_DEV_TARGET}"
			sync
		fi
	fi

	local target_part="$(find_first_hfsplus_part "${G_DEV_TARGET}")"
	if [ -z "${target_part}" ]; then
		$lred; echo "No HFS+ Partition found on ${G_DEV_TARGET}"
	else
		$white; echo "Writing Partition boot code..."; $normal
		dd if="${G_CHAMELEONDIR}/boot1h" of="${target_part}"
		sync
	fi
}
