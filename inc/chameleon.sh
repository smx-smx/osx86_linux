#!/bin/bash
function docheck_chameleon(){
	if is_on PART_GPT; then
		$lred; echo "Cannot install chameleon on GPT drives!"; $normal
	else
		if  [ -f  "$scriptdir/chameleon/boot1h" ] && [ -f  "$scriptdir/chameleon/boot" ]; then
			do_chameleon
		else
			$lred; echo "WARNING: Cannot install Chameleon, critical files missing"
			echo "Your installation won't be bootable"; $normal
		fi
	fi
}

function do_chameleon(){
	$lyellow; echo "Installing chameleon..."; $normal
	cp $verbose "$scriptdir/chameleon/boot" /mnt/osx/target/
	sync

	if [ -d "$scriptdir/chameleon/Themes" ]; then
		$yellow; echo "Copying Themes..."; $normal
		cp -R "$scriptdir/chameleon/Themes" "/mnt/osx/target/Extra/"
	fi
	if [ -d "$scriptdir/chameleon/Modules" ]; then
		$yellow; echo "Copying Modules..."; $normal
		cp -R "$scriptdir/chameleon/Modules" "/mnt/osx/target/Extra/"
	fi
	sync

	$yellow; echo "Flashing boot record..."; $normal
	if [ ! -f  "$scriptdir/chameleon/boot0" ]; then
		$lred; echo "WARNING: MBR BootCode (boot0) Missing."
		echo "Installing Chameleon on Partition Only"; $normal
	else
		local do_instMBR=0
		if [ -z $chameleonmbr ]; then
			read -p "Do you want to install Chameleon on MBR? (y/n)" -n1 -r
			echo
			if [[ $REPLY =~ ^[Yy]$ ]]; then do_instMBR=1; fi
		elif [ "$chameleonmbr" == "true" ]; then do_instMBR=1; fi
	fi
	if [ $virtualdev -eq 1 ]; then
		if [ $do_instMBR -eq 1 ]; then
			dd bs=446 count=1 conv=notrunc if="$scriptdir/chameleon/boot0" of="/dev/nbd0"
			sync
		fi
		dd if="$scriptdir/chameleon/boot1h" of="/dev/nbd0p1"
		sync
	else
		if [ $do_instMBR -eq 1 ]; then
			dd bs=446 count=1 conv=notrunc if="$scriptdir/chameleon/boot0" of="$dev"
		fi
		dd if="$scriptdir/chameleon/boot1h" of="${dev}1"
	fi
	sync
}
