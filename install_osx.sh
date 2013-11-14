#!/bin/bash
normal='tput sgr0'
bold='setterm -bold'

red='printf \033[00;31m'
green='printf \033[00;32m'
yellow='printf \033[00;33m'
blue='printf \033[00;34m'
purple='printf \033[00;35m'
cyan='printf \033[00;36m'
lightgray='printf \033[00;37m'
lred='printf \033[01;31m'
lgreen='printf \033[01;32m'
lyellow='printf \033[01;33m'
lblue='printf \033[01;34m'
lpurple='printf \033[01;35m'
lcyan='printf \033[01;36m'
white='printf \033[01;37m'

debug=1
trap err_exit SIGINT

dmgimgversion="1.6.5"
xarver="1.5.2"

function pause() {
   $white; read -p "$*"; $normal
}

function mediamenu(){
mediamenu=1
if [ $virtualdev == 1 ]; then
	if [ $nbd0_mapped == 0 ]; then
		echo "Mapping $dev..."
		qemu_map "nbd0" "$dev"
		if [ ! $nbd0_mapped == 1 ]; then
			err_exit "Can't map "$dev"\n"
		fi
	fi
	if [ ! -b "/dev/nbd0p1" ]; then
		err_exit "Corrupted image\n"
	#else
		#
		#if [ $virtualdev == 1 ]; then
		#	partlabel=$(udisks --show-info /dev/nbd0p1 | grep -i "label:" | sed -n 1p | sed 's|[\t]||g;s/label://g;s/^[ \t]*//')
		#else
		#	partlabel=$(udisks --show-info ""$dev"1" | grep -i "label:" | sed -n 1p | sed 's|[\t]||g;s/label://g;s/^[ \t]*//')
		#fi
		#partlabel=$(mkfs.hfsplus -N /dev/nbd0p1 | grep name | sed 's|[\t,"]||g' | awk '{print $3}')
		#if [ ! "$partlabel" == "smx_installer" ]; then
		#	echo $partlabel
		#	err_exit "Not an installer image\n"
		#fi
	fi
fi
if [ ! $(mount | grep -q "/mnt/osx/target"; echo $?) == 0 ]; then
	echo "mounting..."
	if [ ! -d /mnt/osx/target ]; then mkdir -p /mnt/osx/target; fi
	if [ $virtualdev == 1 ]; then
		mount -t hfsplus /dev/nbd0p1 /mnt/osx/target
	else
		mount -t hfsplus ""$dev"1" /mnt/osx/target
	fi
	if [ ! $? == 0 ]; then
		err_exit "Cannot mount target\n"
	elif [ ! -d /mnt/osx/target/Extra ]; then
		mkdir -p /mnt/osx/target/Extra/Extensions
	fi
else
	echo "already mounted"
fi
detect_osx_version
echo "Working on "$dev""
echo "Choose an operation..."
echo "1 - Manage kexts"
echo "2 - Reinstall / Update chameleon"
echo "3 - Install / Reinstall MBR Patch"
echo "4 - Install / Reinstall SMBios"
echo "5 - Delete image"
echo "6 - Delete Kext Cache"
echo "0 - Exit"
printf "Choose an option: "; read choice
case "$choice" in
	0)
		err_exit ""
		;;
	1)
		clear
		kextmenu
		err_exit ""
		;;
	2)
		docheck_chameleon
		err_exit ""
		;;
	3)
		docheck_mbr
		err_exit ""
		;;
	4)
		docheck_smbios
		err_exit ""
	;;
	5)
		cleanup "ret"
		if [ $virtualdev == 1 ]; then
			echo "You are about to delete "$dev"?"
			read -p "Are you really sure you want to continue? (y/n)" -n1 -r
			echo
			if [[ $REPLY =~ ^[Nn]$ ]];then
				err_exit ""
			fi
				rm "$dev"
				echo "$(basename $dev) succesfully deleted"
				#else
				#	echo "Can't delete image"
		elif [ $virtualdev == 0 ]; then
			echo "You are about to erase "$dev"?"
			read -p "Are you really sure you want to continue? (y/n)" -n1 -r
			echo
			if [[ $REPLY =~ ^[Nn]$ ]];then
				err_exit ""
			fi
				dd if=/dev/zero of="$dev" bs=512 count=1
				echo "$dev succesfully erased"
		fi
		err_exit ""
		;;
	6)
		do_remcache
		err_exit ""
		;;
	*)
		pause "Invalid option, press [enter] to try again"
		clear
		mediamenu
esac
}

function kextmenu(){
kexts=$(find "$kextdir" -maxdepth 1 -type d -name "*.kext" | wc -l)
if [ $kexts == 0 ]; then
	echo "No kext to install"
	pause "Press [enter] to return to menu"
	mediamenu
fi
printf "Choose a kext to Install / Reinstall: "
	local k
	local eskdir=$(echo "$kextdir" | sed 's/\ /\\\//g;s/\//\\\//g')
	echo "0 - Return to main menu"
	for k in `seq $kexts`; do
		local option=$(find "$kextdir" -maxdepth 1 -type d -name "*.kext" | sed "s/$eskdir\///g" | sed -n "$k"p)
			eval kext$k=$option
			#if [ -d "/mnt/osx/target/System/Library/Extensions/"$option"" ]; then
			if [ -d "/mnt/osx/target/Extra/Extensions/"$option"" ]; then
				printf "[*]\t$k - $option\n"
			else
				printf "[ ]\t$k - $option\n"
			fi
	done
	echo "Choose a kext to install/uninstall"
	read choice
	local name="kext$choice"
	#echo "${!name}"
	#eval echo \$kext$choice
	if [ "$choice" == "0" ]; then
		clear
		mediamenu
	fi
	if [ -z "${!name}" ]; then
		pause "Invalid option, press [enter] to try again"
		clear
		kextmenu
	else
	clear
		#if [ -d "/mnt/osx/target/System/Library/Extensions/${!name}" ]; then
		if [ -d "/mnt/osx/target/Extra/Extensions/${!name}" ]; then
			echo "Removing ${!name}..."
			#rm -R "/mnt/osx/target/System/Library/Extensions/${!name}"
			rm -R "/mnt/osx/target/Extra/Extensions/${!name}"
		else
			echo "Installing ${!name}..."
			#cp -R "$scriptdir/extra_kexts/${!name}" /mnt/osx/target/System/Library/Extensions/
			#chmod -R 755 "/mnt/osx/target/System/Library/Extensions/${!name}"
			cp -R "$scriptdir/extra_kexts/${!name}" /mnt/osx/target/Extra/Extensions/
			chmod -R 755 "/mnt/osx/target/Extra/Extensions/${!name}"
		fi
	fi
	echo "Done!"
	kextmenu
}

function vdev_check(){
echo "Virtual Device"
	virtualdev=1
	touchedfile=0
	deletedfile=0
	if ! check_command 'qemu-nbd' == 0; then
		err_exit ""
	fi
	if [ ! -e "$1" ]; then 
		touchedfile=1
		touch "$1"
		if [ $debug == 1 ]; then echo "touchfile"; fi
	fi

	mountdev=$(df -P "$1" | tail -1 | cut -d' ' -f 1) #which partition holds the image
	mountfs=$(udisks --show-info "$mountdev" | grep "type:" | sed -n 1p | sed 's|[\t, ]||g;s/type\://g') #filesystem type of partition
	mounttype=$(mount | grep "$mountdev" | awk '{print $5}') #mount method reported my "mount"
	checkro=$(udisks --show-info "$mountdev" | grep "is read only" | awk '{print $4}')
	if [ ! -b "$mountdev" ]; then
		err_exit "Can't get virtual image device\n"
	fi	
	if [ ! "$checkro" == "0" ] && [ ! "$checkro" == "1" ]; then
		err_exit "Can't get readonly flag\n"
	fi
	if [ $touchedfile == 1 ] && [ -f "$1" ]; then
		rm "$1"
		deletedfile=1
		if [ $debug == 1 ]; then echo "deletefile"; fi
	fi
	if [ $checkro == 1 ]; then
		err_exit "Can't write image on read only filesystem\n"
	fi
	if [ "$mountfs" == "ntfs" ] && [ "$mounttype" == "fuseblk" ]; then
		echo "WARNING, FUSE DETECTED!, READ/WRITE OPERATION MAY BE SLOW"
		echo "ext4 filesystem is preferred"
		read -p "Are you sure you want to continue? (y/n)" -n1 -r
		echo
		if [[ $REPLY =~ ^[Nn]$ ]];then
			err_exit ""
		fi
	fi
	if [ ! -f "$1" ] && [ "$dextension" == ".vdi" ]; then
		vbhdd=1; format=VDI
	elif [ ! -f "$1" ] && [ "$dextension" == ".vhd" ]; then
		vbhdd=1; format=VHD
	elif [ ! -f "$1" ] && [ "$dextension" == ".vmdk" ]; then
		vbhdd=1; format=VMDK
	elif [ -f "$1" ]; then
		dev=$1
		clear; mediamenu
		#err_exit "$1 already exists. Exiting\n"
	#else
	#	err_exit "Unknown Error!\n"
	fi
	if [ "$size" == "" ] || [ "$size" == " " ] || [ -z $size ]; then
		size=$((10 * 1024 * 1024 * 1024)) #10gb
	fi
	check_space "$file" "$size" 1
	isdev=$(echo "$1" | grep -q "/dev/"; echo $?)
	if [ $isdev == 0 ]; then
		err_exit "Something wrong, not going to erase $dev\n"
	fi
}

function main(){
export -f payload_extractor
mediamenu=0
if [ "$1" == "-h" ] || [ "$1" == "--help" ] || [ "$1" == "help" ] || [ "$1" == "?" ] || [ "$1" == "/?" ]; then
	usage
	err_exit ""
fi
$lgreen; printf "OSX Install Media Maker by "
$lyellow; printf "S"
$lblue; printf "M"
$lpurple; printf "X\n"
$normal

scriptdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd -P)"
kextdir="$scriptdir/extra_kexts"
filepath="$( cd "$( dirname "$1" )" && pwd -P)"
devpath="$( cd "$( dirname "$2" )" && pwd -P)"
cd $scriptdir
script=$scriptdir
script+=/$(basename $0)

for ((c=0;c<3;c++)); do
	local vartmp="nbd"$c"_mapped"
	eval ${vartmp}=0
done

##File Details
#name --> filename.extension
#extension --> ".img", ".tar", ".dmg",..
#filename --> filename without extension
file=$1
dev=$2
size=$3 #for img creation
user=$4

virtualdev=0
vbhdd=0

if [[ ! "$OSTYPE" == linux* ]]; then
	err_exit "This script can only be run under Linux\n"
fi

if [ "$(id -u)" != "0" ]; then
   err_exit "This script must be run as root\n"
fi

if [ -z $commands_checked ]; then	commands_checked=0; fi
if [ $commands_checked == 0 ]; then
	check_commands	#Check all required commands exist
	commands_checked=1
	export commands_checked
fi

find_cmd "xar" "xar_bin/bin"
find_cmd "dmg2img" "dmg2img_bin/usr/bin"

c_d2iver=$(dmg2img 2>&1| grep v | sed -n 1p | awk '{print $2}' | sed 's/v//g')
if [ ! "$d2iver" == "$dmgimgversion" ] && [ "$dmg2img" == "dmg2img" ]; then
	echo "WARNING! dmg2img is not updated and may cause problems"
	echo "Detected version: "$d2iver""
	echo "Recommanded version: "$dmgimgversion""
	read -p "Compile version "$dmgimgversion"? (y/n)" -n1 -r
	echo
	if [[ $REPLY =~ ^[Yy]$ ]];then
		echo "Compiling dmg2img..."
		compile_d2i
	fi
fi

do_init_qemu
if [ ! -d /mnt/osx ]; then mkdir -p /mnt/osx; fi
if [ ! -d /mnt/osx/esd ]; then mkdir /mnt/osx/esd; fi
if [ ! -d /mnt/osx/base ]; then mkdir /mnt/osx/base; fi
if [ ! -d /mnt/osx/target ]; then mkdir /mnt/osx/target; fi

local iscdrom=$(echo "$1" | grep -q "/dev/sr[0-9]" ;echo $?)
if [ -b "$1" ] && [ "$iscdrom" == "0" ]; then
	echo "CD Source Device Detected"
	if [ -z $2 ] || [ "$2" == "" ] || [ "$2" == " " ]; then
		err_exit "You must specify a valid destination to create an img file\n"
	elif [ -d "$2" ]; then
		err_exit "You must provide a filename\n"
	elif [ -f "$2" ]; then
		err_exit "$2 already exists\n"
	else
		echo "Img creation is in progress..."
		echo "The process may take some time"
		if [ ! -d "$(dirname "$2")" ]; then
			mkdir -p "$(dirname "$2")"
		fi
		if [ ! -d "$(dirname "$2")" ]; then
			err_exit "Can't create destination folder\n"
		fi
		dd if="$1" of="$2"
		watch -n 10 kill -USR1 `pidof dd`
	fi
fi

if [ -b "$1" ] && [ ! -f "$1" ] && [ ! -d "$1" ] && [ -z "$2" ] && [ -z "$3" ]; then
	dev="$1"
	mediamenu
#elif [ -f "$1" ] && [ -z "$2" ] && [ -z "$3" ]; then
#	virtualdev=1
#	mediamenu
fi

name=$(basename "$1")
extension=".${name##*.}"
filename="${name%.*}"

dname=$(basename "$2")
dextension=".${dname##*.}"
dfilename="${dname%.*}"

if [ "$extension" == ".pkg" ] || [ "$extension" == ".mpkg" ]; then
	if [ -z "$2" ] || [ "$2" == "" ] || [ "$2" == " " ]; then
		usage
		err_exit "Invalid Destination Folder\n"
	fi
	extract_pkg "$file" "$2"
	exit 0
elif [ ! -f "$file" ] || [ ! "$extension" == ".dmg" ]; then
	if [ "$extension" == ".img" ] || [ "$extension" == ".vhd" ] || [ "$extension" == ".vdi" ] || [ "$extension" == ".vmdk" ]; then
		vdev_check "$file"
	else
		usage
		err_exit "Invalid file specified\n"
	fi
fi
if [ -z "$dev" ] || [ "$dev" == "" ] || [ "$dev" == " " ]; then
	usage
	err_exit "You must specify a valid target drive or image\n"
fi

if [ ! -b "$dev" ]; then
	vdev_check "$dev"
fi

if [ $virtualdev == 1 ] && [ ! $vbhdd == 1 ]; then
	echo "Creating Image..."
	dd if=/dev/zero bs=1 of="$dev"  seek="$size" count=0
	sync; sync; sync; sync
	if [ ! $? == 0 ]; then
		err_exit "Error during image creation\n"
	fi
elif [ $virtualdev == 1 ] && [ $vbhdd == 1 ]; then
		if ! check_command 'vboxmanage' == 0; then
			err_exit ""
		fi
		echo "WARNING, VIRTUALBOX OUTPUT EXTENSION DETECTED!"
		echo "QEMU SUPPORT FOR VIRTUALBOX HARD DISKS  MAY NOT BE FULLY STABLE"
		echo "img output is recommended. You will be asked if you want to convert the img to vdi at the end of the process"
		read -p "Are you sure you want to continue with virtualbox format? (y/n)" -n1 -r
		echo
		if [[ $REPLY =~ ^[Nn]$ ]];then
			err_exit ""
		fi
		vboxmanage createhd --filename "$dev" --sizebyte $size --format "$format" --variant Standard
		if [ ! $? == 0 ]; then
			err_exit "Error during Virtual Hard Disk Creation\n"
		fi
elif [ $virtualdev == 0 ] && [ $vbhdd == 0 ]; then
	if [[ $dev = *[0-9] ]]; then
		usage
		err_exit "You must specify the whole device, not a single partition!\n"
	fi
	partmap=$(ls -1 "$dev"*[0-9])
	for part in $partmap; do
		echo "Part: $part"
		checkmounted=$(mount | grep -q "$part"; echo $?)
		if [ $checkmounted == 0 ]; then
			umount "$part"
		fi
		checkmounted=$(mount | grep -q "$part"; echo $?)
		if [ $checkmounted == 0 ]; then
			err_exit "Couldn't unmount "$part"\n"
		fi
	done
	checkmounted=$(mount | grep -q "$dev"; echo $?)
	if [ $checkmounted == 0 ]; then
		err_exit ""$dev" is still mounted\n"
	fi
	checkrem=$(udisks --show-info "$dev" | grep "removable" | awk '{print $2}')
	echo "isRemovable = $checkrem"
	if [ ! $checkrem == 0 ] && [ ! $checkrem == 1 ]; then
		err_exit "Can't get removable flag\n"
	fi
	
	if [ "$checkrem" == "0" ]; then
		echo "WARNING, "$dev" IS NOT A REMOVABLE DEVICE!"
		echo "ARE YOU SURE OF WHAT YOU ARE DOING?"
		read -p "Are you REALLY sure you want to continue? (y/n)" -n1 -r
		echo
		if [[ $REPLY =~ ^[Nn]$ ]];then
			err_exit "Exiting\n"
		fi
	fi

	echo "WARNING, ALL THE CONTENT OF "$dev" WILL BE LOST!"
	read -p "Are you sure you want to continue? (y/n)" -n1 -r
	echo
	if [[ $REPLY =~ ^[Nn]$ ]];then
		err_exit "Exiting\n"
	fi
else
	err_exit "Unknown Operation Mode\n"
fi

if [ $vbhdd == 1 ]; then
	echo "Mapping virtual dev with qemu..."
	qemu-nbd -d /dev/nbd0 &>/dev/null
	sleep 1
	qemu-nbd -c /dev/nbd0 "$dev"
	if [ ! $? == 0 ]; then
		err_exit "Error during nbd mapping\n"
	fi	
fi

echo "Creating Partition Table on $dev..."
if [ $vbhdd == 0 ]; then
	parted -a optimal "$dev" mklabel msdos
else
	parted -a optimal "/dev/nbd0" mklabel msdos
fi

if [ ! $? == 0 ]; then
	err_exit "Error during partition table creation\n"
fi

echo "Creating new Primary Active Partition on $dev"
if [ $vbhdd == 0 ]; then
	parted -a optimal "$dev" --script -- mkpart primary hfs+ "1" "-1"
else
	parted -a optimal "/dev/nbd0" --script -- mkpart primary hfs+ "1" "-1"
fi
if [ ! $? == 0 ]; then
	err_exit "Error: cannot create new partition\n"
fi
if [ $vbhdd == 0 ]; then
	parted -a optimal "$dev" print
	parted -a optimal "$dev" set 1 boot on
else
	parted -a optimal "/dev/nbd0" print
	parted -a optimal "/dev/nbd0" set 1 boot on
fi
sync
if [ $virtualdev == 1 ] && [ $vbhdd == 0 ]; then
	if [ ! $nbd0_mapped == 1 ]; then
		echo "Mapping virtual dev with qemu..."
		qemu_map "nbd0" "$dev"
		if [ ! $nbd0_mapped == 1 ]; then
			err_exit "Error during nbd mapping\n"
		fi
	fi
fi

echo "Formatting partition as HFS+"
if [ $virtualdev == 1 ]; then
	mkfs.hfsplus /dev/nbd0p1 -v "smx_installer"
else
	mkfs.hfsplus ""$dev"1"
fi
if [ ! $? == 0 ]; then
	err_exit "Error during HFS+ formatting\n"
fi

outfile=""$filepath/$filename".img"
if [ ! -e "$outfile" ]; then
	echo "Converting "$file" to img..."
	$dmg2img "$file" "$outfile"
#check_err=$(cat /tmp/dmg2img.log | grep -q "ERROR:"; echo $?)
#if [ ! $? == 0 ] || [ ! -f "$outfile" ] || [ $check_err == 0 ]; then
if [ ! $? == 0 ] || [ ! -f "$outfile" ]; then
	rm "$outfile"
	err_exit "Img conversion failed\n"
fi
unset check_err
fi

echo "Mapping image with qemu..."
if [ ! $nbd1_mapped == 1 ]; then
	qemu_map "nbd1" "$outfile"
	if [ ! $nbd1_mapped == 1 ]; then
		err_exit "Error during image mapping\n"
	fi
fi

echo "Mounting Partitions..."
if [ $virtualdev == 0 ]; then 
	umount ""$dev"1"
fi

mount -t hfsplus /dev/nbd1p2 /mnt/osx/esd &>/dev/null
if [ ! $? == 0 ]; then
	mount -t hfsplus /dev/nbd1p3 /mnt/osx/esd &>/dev/null
	if [ ! $? == 0 ]; then
		err_exit "Cannot mount esd\n"
	fi
fi

detect_osx_version

if [ ! "$osver" == "10.6" ]; then
	outfile=""$filepath"/BaseSystem.img"
	if [ ! -e "$outfile" ]; then
		echo "Converting BaseSystem.dmg..."
		$dmg2img "/mnt/osx/esd/BaseSystem.dmg" "$outfile"
		if [ ! $? == 0 ] || [ ! -f "$outfile" ]; then
			err_exit "Img conversion failed\n"
		fi
	fi

	echo "Mapping BaseSystem with qemu..."
	if [ ! $nbd2_mapped == 1 ]; then
		qemu_map "nbd2" "$outfile"
		if [ ! $nbd2_mapped == 1 ]; then
			err_exit "Error during BaseSystem mapping\n"
		fi
	fi

	mount -t hfsplus /dev/nbd2p2 /mnt/osx/base
	if [ ! $? == 0 ]; then
		err_exit "Cannot mount BaseSystem\n"
	fi
	detect_osx_version
fi

if [ $virtualdev == 1 ]; then
	mount -t hfsplus /dev/nbd0p1 /mnt/osx/target
else
	mount -t hfsplus ""$dev"1" /mnt/osx/target
fi
if [ ! $? == 0 ]; then
	err_exit "Cannot mount target\n"
elif [ ! -d /mnt/osx/target/Extra ]; then
	mkdir -p /mnt/osx/target/Extra/Extensions
fi

do_system
docheck_mbr
sync

#if [ ! $(ls -1 "$kextdir/*.kext" | wc -l) == 0 ]; then
	echo "Installing kexts in \"extra_kexts\" directory"
	kextdir="$scriptdir/extra_kexts"
	for kext in $kextdir/*.kext; do
		echo " Installing $(basename $kext)..."
		#cp -Rv "$kext" /mnt/osx/target/System/Library/Extensions/
		#chmod -R 755 "/mnt/osx/target/System/Library/Extensions/$(basename $kext)"
		cp -Rv "$kext" /mnt/osx/target/Extra/Extensions/
		chmod -R 755 "/mnt/osx/target/Extra/Extensions/$(basename $kext)"
	done
	sync
#fi

do_remcache
docheck_chameleon
docheck_smbios

if [ $virtualdev == 1 ]; then
	if  [ ! -z $username ] || [ ! "$username" == "" ] || [ ! "$username" == " " ]; then
		chmod 666 "$dev"
		chown "$user" "$dev"
	fi
fi
sync
cleanup
echo "All Done!"
if [ $virtualdev == 1 ] && [ "$dextension" == ".img" ]; then
	read -p "Do you want to convert virtual image to a VDI file? (y/n)" -n1 -r
	echo
	if [[ $REPLY =~ ^[Yy]$ ]];then
		vboxmanage convertdd  "$dev" ""$devpath/$dfilename".vdi"
		if [ ! $? == 0 ] || [ ! -f ""$devpath/$dfilename".vdi" ]; then
			err_exit "Conversion Failed\n"
		else
			read -p "Do you want to delete the img file? (y/n)" -n1 -r
			echo
			if [[ $REPLY =~ ^[Yy]$ ]];then
				rm "$dev"
			fi
		fi
	fi
fi
exit 0

}

function do_init_qemu(){
	echo "Setting qemu-nbd dev..."
	remove_nbd=0
	nbd_reloaded=0
	if [ ! -b /dev/nbd0 ]; then
		modprobe nbd max_part=10
		sleep 1
		if [ ! -b /dev/nbd0 ]; then
			err_exit "Error while loading module \"nbd\"\n"
		fi
		remove_nbd=1
	else
		echo "Reloading nbd..."
		echo "Checking for mounts..."
		local nbdmnt=$(mount | grep -q "/dev/nbd"; echo $?)
		if [ $nbdmnt == 0 ]; then
			nbdmnt=($(mount | grep "/dev/nbd" | awk '{print $1}'))
			local anbd=$(ls -1 /dev/nbd*p* | sed '$s/..$//')
			for mount in $nbdmnt; do
				echo "Unmounting "$mount"..."
				local ures=$(umount $mount; echo $?)
				if [ ! $ures == 0 ]; then
					err_exit "Can't unmount "$mount"\n"
				fi
			done
		fi
		for ndev in $anbd; do
			qemu-nbd -d $ndev &>/dev/null
			if [ ! $? == 0 ]; then
				err_exit "Error during nbd unmapping\n"
			fi
		done
		rmmod nbd
		modprobe nbd max_part=10
		remove_nbd=1	
		nbd_reloaded=1
	fi
	if [ ! -b /dev/nbd0 ]; then
		err_exit "Cannot load qemu nbd kernel module\n"
	fi
}

function qemu_map(){
	qemu-nbd -d /dev/"$1" &>/dev/null
	sleep 0.3
	qemu-nbd -c /dev/"$1" "$2"
	local res=$?
	sleep 0.3
	vartmp="$1_mapped"
	if [ $res == 0 ]; then
		eval ${vartmp}=1
	fi
}

function docheck_smbios(){
if [ -f "$/scriptdir/smbios.plist" ]; then
	cp "$/scriptdir/smbios.plist" /mnt/osx/target/Extra/smbios.plist
else
	echo "Skipping smbios.plist, file not found"
	if [ ! "$osver" == "10.6" ]; then
		echo "Warning: proper smbios.plist may be needed"
	fi
fi
}

function docheck_chameleon(){
if [ -f  "$scriptdir/chameleon/boot0" ] && [ -f  "$scriptdir/chameleon/boot1h" ] && [ -f  "$scriptdir/chameleon/boot" ]; then
	do_chameleon
else
	echo "WARNING: Cannot install Chameleon, critical files missing"
	echo "Your installation won't be bootable"
fi
}

function docheck_mbr(){
if [ -d "$scriptdir/osinstall_mbr" ] && [ -f "$scriptdir/osinstall_mbr/OSInstall.mpkg" ] && [ -f "$scriptdir/osinstall_mbr/OSInstall" ]; then
	check_mbrver
	if [ "$dombr" == "1" ]; then
		do_mbr
	fi
fi
}

function check_mbrver(){
if [ -d "$scriptdir/osinstall_mbr/tmp" ]; then rm -r "$scriptdir/osinstall_mbr/tmp"; fi
echo "Checking patch version..."
extract_pkg "$scriptdir/osinstall_mbr/OSInstall.mpkg" "$scriptdir/osinstall_mbr/tmp/p"
if [ -f "/mnt/osx/target/Packages/OSInstall.mpkg" ]; then # esd
	echo "Checking original version..."
	extract_pkg "/mnt/osx/target/Packages/OSInstall.mpkg" "$scriptdir/osinstall_mbr/tmp/o"
else #target
	echo "Checking original version..."
	extract_pkg "/mnt/osx/target/System/Installation/Packages/OSInstall.mpkg" "$scriptdir/osinstall_mbr/tmp/o"
fi
local origver=$(cat "$scriptdir/osinstall_mbr/tmp/o/Distribution" | grep system.version | grep -o 10.* | awk '{print $1}' | sed "s|['\)]||g")
local origbuild=$(cat "$scriptdir/osinstall_mbr/tmp/o/Distribution" | grep pkg.Essentials | grep -o "version.*" | sed 's/version=//g;s|["/>]||g')
local patchver=$(cat "$scriptdir/osinstall_mbr/tmp/p/Distribution" | grep system.version | grep -o 10.* | awk '{print $1}' | sed "s|['\)]||g")
local patchbuild=$(cat "$scriptdir/osinstall_mbr/tmp/p/Distribution" | grep pkg.Essentials | grep -o "version.*" | sed 's/version=//g;s|["/>]||g')
if [ ! "$origver" == "$osver" ]; then
	printf "Package:\t$origver\nOS:\t$osver\n"
	echo "WARNING: NOT APPLYING MBR PATCH"
	echo "MPKG DOESN'T MATCH OS VERSION!"
	dombr=0
elif [ ! "$patchver" == "$osver" ] || [ ! "$patchver" == "$origver" ] || [ ! "$patchbuild" == "$origbuild" ]; then
	echo "WARNING: NOT APPLYING MBR PATCH"
	echo "INCOMPATIBLE VERSIONS"
	printf "Original:\t$origbuild\nPatch:\t\t$patchbuild\n"
	dombr=0
else
	dombr=1
fi
}

function do_remcache(){
echo "Deleting Kext Cache..."
if [ -f /mnt/osx/target/System/Library/Caches/kernelcache ]; then
	rm /mnt/osx/target/System/Library/Caches/kernelcache
fi
}

function do_mbr(){
	echo "Patching Installer to support MBR"
	cp -v "$scriptdir/osinstall_mbr/OSInstall.mpkg" "/mnt/osx/target/System/Installation/Packages/OSInstall.mpkg"
	cp -v "$scriptdir/osinstall_mbr/OSInstall" "/mnt/osx/target/System/Library/PrivateFrameworks/Install.framework/Frameworks/OSInstall.framework/Versions/A/OSInstall"
}

function do_chameleon(){
	echo "Installing chameleon..."	
	cp "$scriptdir/chameleon/boot" /mnt/osx/target/
	sync
	
	if [ -d "$scriptdir/Themes" ]; then
		cp -R "$scriptdir/Themes" "/mnt/osx/target/Extra/Themes"
	fi
	if [ -d "$scriptdir/Modules" ]; then
		cp -R "$scriptdir/Modules" "/mnt/osx/target/Extra/Modules"
	fi
	sync
	
	umount /mnt/osx/target
	sync; sync
	
	if [ $virtualdev == 1 ]; then
		dd bs=440 count=1 conv=notrunc if="$scriptdir/chameleon/boot0" of="/dev/nbd0"
		sleep 0.5
		sync
		sleep 0.5
		dd if="$scriptdir/chameleon/boot1h" of="/dev/nbd0p1"
		sleep 0.5
		sync
		sleep 0.5
	else
		dd bs=440 count=1 conv=notrunc if="$scriptdir/chameleon/boot0" of="$dev"
		dd if="$scriptdir/chameleon/boot1h" of=""$dev"1"
	fi
	sync
}

function do_system(){
	echo "Copying Base System to "$dev"..."
	#rsync -arpv --progress /mnt/osx/base/* /mnt/osx/target/
	if [ "$osver" == "10.6" ]; then
		cp -pdRv /mnt/osx/esd/* /mnt/osx/target/
	else
		cp -pdRv /mnt/osx/base/* /mnt/osx/target/
		echo "Copying installation packages to "$dev"..."
		rm /mnt/osx/target/System/Installation/Packages
		mkdir /mnt/osx/target/System/Installation/Packages
		cp -pdRv /mnt/osx/esd/Packages/* /mnt/osx/target/System/Installation/Packages
		sync
		echo "Copying kernel..."
		if [ "$osver" == "10.9" ]; then
			echo "Kernel is in BaseSystemBinaries.pkg, extracting..."
			extract_pkg "/mnt/osx/esd/Packages/BaseSystemBinaries.pkg" "$scriptdir/tmp/bsb" "skip"
			cp -av "$scriptdir/tmp/bsb/mach_kernel" "/mnt/osx/target/"
		#elif [ ! "$osver" == "10.6" ]; then
		else
			if [ -f "/mnt/osx/esd/mach_kernel " ]; then cp -av /mnt/osx/esd/mach_kernel /mnt/osx/target/; fi
		fi
		if [ ! -f /mnt/osx/target/mach_kernel ]; then
			echo "WARNING! Kernel Copy Error!!"
			echo "Media won't boot without kernel!"
		fi
	fi
	sync
	#rsync -arpv --progress /mnt/osx/esd/Packages/* /mnt/osx/target/System/Installation/Packages 
}

function detect_osx_version(){
	if [ "$mediamenu" == "1" ]; then #look in target
		echo "verfile -> target"
		local verfile="/mnt/osx/target/System/Library/CoreServices/SystemVersion.plist"
	else #look in esd (snow leopard?)
		echo "verfile -> esd"
		local verfile="/mnt/osx/esd/System/Library/CoreServices/SystemVersion.plist"
	fi
	if [ ! -f "$verfile" ]; then
		if [ -f "/mnt/osx/esd/BaseSystem.dmg" ] && [ ! -f "/mnt/osx/base/System/Library/CoreServices/SystemVersion.plist" ]; then
			osname="notsnow"
			osver="10.7+"
		elif [ -f "/mnt/osx/base/System/Library/CoreServices/SystemVersion.plist" ] && [ ! "$mediamenu" == "1" ]; then
			echo "verfile -> base"
			local verfile="/mnt/osx/base/System/Library/CoreServices/SystemVersion.plist"
			osname=""
			osver=""
		elif [ "$mediamenu" == "1" ]; then
			osname="none"
			osver=""
			echo "Warning: Can't detect OSX Build"
		else
			err_exit "Can't detect OSX Build\n"
		fi
	fi
	
	local tq=0  #to quit
if [ ! "$osname" == "notsnow" ] && [ ! "$osname" == "none" ]; then
		osbuild=$(cat "$verfile" | grep -A1 "<key>ProductBuildVersion</key>" | sed -n 2p | sed 's|[\t <>/]||g;s/string//g')
		osver=$(cat "$verfile" | grep -A1 "<key>ProductVersion</key>" | sed -n 2p | sed 's|[\t <>/]||g;s/string//g')
	
	if [ "$osver" == "10.6" ]; then
		osname="Snow Leopard"
	elif [ "$osver" == "10.7" ]; then
		osname="Lion"
	elif [ "$osver" == "10.8" ]; then
		osname="Mountain Lion"
	elif [ "$osver" == "10.9" ]; then
		osname="Mavericks"
	elif [ ! "$osver" == "" ] && [ ! "$osbuild" == "" ]; then
		osname="Not supported"
		osver="version"
		local tq=1
	else
		osname="Unknown"
		osver="version"
		local tq=1
	fi
fi

	if [ $tq == 1 ]; then
		err_exit ""$osname" "$osver" detected\n"
	else
		echo ""$osname" "$osver" detected"
	fi
}
	

function check_space {
		local strict=$3
		freespace=$(( $(df "$1" | sed -n 2p | awk '{print $4}') * 1024))
		if [ $debug == 1 ]; then printf "FreeSpace:\t$freespace\n"; printf "Needed:\t\t$2\n"; fi
		if [ $freespace -ge $2 ]; then
			return 0
		else
			if [ $strict == 1 ]; then err_exit "Not enough free space\n"; else return 1; fi
		fi
}

function check_commands {
	$lyellow; echo "Checking Commands..."
	$normal
	if [ $commands_checked == 1 ]; then
		#add checks for other commands after the initial check
		echo &>/dev/null
	else
		commands=('udisks' 'grep' 'tput' 'dd' 'sed' 'parted' 'awk' 'mkfs.hfsplus' 'wget' 'dirname' 'basename' 'dmg2img' 'parted' 'pidof' 'gunzip' 'bunzip2' 'cpio')
	fi
	for command in "${commands[@]}"; do
		if ! check_command $command == 0; then
			$normal
			cleanup
			exit
		fi
		$normal
	done
}

function checkfile {
	local file=$1
	if [ ! -e "$1" ]; then
		return 1
	else
		return 0
	fi
}

function find_cmd {
cmd=$1
cmdir=$2
if [ ! -z "$cmdir" ]; then
	eval ${cmd}="$scriptdir/$cmdir/$cmd"
else
	eval ${cmd}="$scriptdir/$cmd"
fi

if ! checkfile "${!cmd}" == 0; then
	eval ${cmd}="./$cmd"
fi
if ! checkfile "${!cmd}" == 0; then
	which $cmd &>/dev/null
	if [ ! $? == 0 ]; then #command not found
		unset ${cmd} #unset cmd location var
		unset cmd #unset cmd var
	else #command located
		eval ${cmd}=$cmd #cmd location is cmd
	fi
fi

#echo "Arg   --> $cmd"
#echo "Var   --> ${cmd}"
#echo "Value --> ${!cmd}"
}

function check_command {
	local command=$1
	echo $command | grep -q '\$'
	if [ $? == 0 ]; then
		command_name=$(echo $command | sed -e 's/\$//g')
		command=${!command_name}
	else
		command_name=$command
	fi
	
	type -P "$command" &>/dev/null
	local cmdstat=$?
	
	if [ -z "$command" ] || [ "$command" == "" ]; then
		cmdstat=1
	fi
	$lcyan; printf "$command_name: "
	if [ $cmdstat == 0 ]; then
		$lgreen; printf "Found\n"; $normal
		return 0
	elif [ $cmdstat == 1 ]; then 
		$lred; printf "Not Found\n"; $normal
		if [ "$command" = "ls" ]; then
			echo "Cygwin Seems Corrupted!"
		fi
		return 1
	else
		$lightgray; printf "Unknown Error\n"; $normal
		return 2
	fi
}

function pause() {
   $white; read -p "$*"; $normal
}

function err_wexit() {
	if [ $clear == 1 ]; then clear; fi
	$lred; printf "$1"; $normal
	echo "Press [Enter] to exit"
	pause
	cleanup
	exit 1
}

function err_exit() {
	$lred; printf "$1"; $normal
	cleanup
	exit 1
}

function cleanup(){
sync; sync
local esd_umount=0
local base_umount=0
local target_umount=0
	if [ -d "$scriptdir/tmp" ]; then rm -r "$scriptdir/tmp"; fi
	if [ $(mount | grep -q "/mnt/osx/esd"; echo $?) == 0 ]; then umount `mount | grep "/mnt/osx/esd" | awk '{print $3}'`; fi
	if [ $(mount | grep -q "/mnt/osx/base"; echo $?) == 0 ]; then umount `mount | grep "/mnt/osx/base" | awk '{print $3}'`; fi
	if [ $(mount | grep -q "/mnt/osx/target"; echo $?) == 0 ]; then umount `mount | grep "/mnt/osx/target" | awk '{print $3}'`; fi

	if [ ! $(mount | grep -q "/mnt/osx/esd"; echo $?) == 0 ]; then
		if [ -d "/mnt/osx/esd" ] && [ $(ls -1 "/mnt/osx/esd" | wc -l ) == 0 ]; then
			rm -r "/mnt/osx/esd"
		fi
		esd_umount=1
	else
		echo "ERROR: Can't unmount esd!"
	fi
	if [ ! $(mount | grep -q "/mnt/osx/base"; echo $?) == 0 ]; then
		if [ -d "/mnt/osx/base" ] && [ $(ls -1 "/mnt/osx/base" | wc -l ) == 0 ]; then
			rm -r "/mnt/osx/base"
		fi
		base_umount=1
		else
		echo "ERROR: Can't unmount basesystem!"
		local base_umount=1
	fi
	
	if [ ! $(mount | grep -q "/mnt/osx/target"; echo $?) == 0 ]; then
		if [ -d "/mnt/osx/target" ] && [ $(ls -1 "/mnt/osx/target" | wc -l ) == 0 ]; then
			rm -r "/mnt/osx/target"
		fi
		target_umount=1
		else
		echo "ERROR: Can't unmount target!"
		local target_umount=1
	fi
	if [ -d "/mnt/osx" ] && [ $(ls -1 "/mnt/osx" | wc -l) == 0 ]; then
		rm -r "/mnt/osx"
	fi
	if [ $esd_umount == 1 ] && [ $base_umount == 1 ] && [ $target_umount == 1 ]; then
		if [ -b /dev/nbd0 ]; then
			for d in $(ls /dev/nbd?); do
				qemu-nbd -d $d &>/dev/null
			done
		fi
		if [ "$remove_nbd" == "1" ]; then
			local res=$(rmmod nbd 2>&1)
			echo $res | sed 's/ERROR:\ //g' #be friendly :)
			if [ "$nbd_reloaded" == "1" ]; then
				modprobe nbd
			fi
		fi
		if [ "$ndb_reloaded" == "1" ]; then
			modprobe nbd
		fi
		if [ ! -z $touchedfile ] && [ ! -z $deletedfile ] &&  [ $touchedfile -eq 1 ] && [ $deletedfile -eq 0 ] && [ $virtualdev -eq 1 ] && [ -e "$dev" ] && [ ! -b "$dev" ]; then rm "$dev"; fi
	else
		echo "Some partitions couldn't be unmounted. Check what's accessing them and unmount them manually"
		if [ "$1" == "ret" ]; then err_exit ""; fi
	fi
#fi
}

function payload_extractor(){
	cd "$(dirname "$1")"
	#echo "$(pwd -P)"
	local fmt=$(file --mime-type $(basename "$1") | awk '{print $2}' | grep -o x.* | sed 's/x-//g')
	local unarch
	if [ "$fmt" == "gzip" ]; then
		unarch="gunzip"
	elif [ "$fmt" == "bzip2" ]; then
		unarch="bunzip2"
	fi
	cat "$(basename "$1")" | $unarch -dc | cpio -i &>/dev/null
	if [ ! $? == 0 ]; then
		echo "WARNING: "$(dirname "$1")" Extraction failed"
	fi
	cd "$dest"
}

function extract_pkg(){
	cd "$scriptdir"
	pkgfile="$1"
	dest="$2"
	if [ ! -d "$dest" ] && [ ! -e "$dest" ]; then
		mkdir -p "$dest"
	#elif [ ! $(ls "$dest" | wc -l) == 0 ]; then
	#	usage
	#	err_exit "Invalid Destination\n"
	fi
	if [ -z "$xar" ]; then
		echo "Compiling xar..."
		compile_xar
		cd "$scriptdir"
		cd "$dest"
		echo "Looking for compiled xar..."
		find_cmd "xar" "xar_bin/bin"
		if [ -z "$xar" ]; then
			err_exit "Something wrong, xar command missing\n"
		fi
	else
		local chkxar=$(xar --version 2>&1 | grep -q "libxar.so.1"; echo $?)
		if [ $chkxar == 0 ]; then
			echo "xar is not working. recompiling..."
			rm -r xar_bin/*
			echo "Recompiling xar..."
			compile_xar
			cd "$scriptdir"
			cd "$dest"
			local chkxar=$(xar -v 2>&1 | grep -q "libxar.so.1"; echo $?)
			if [ $chkxar == 0 ]; then
				err_exit "xar broken, cannot continue\n"
			fi
		fi
	fi
	cd "$scriptdir"
	local fullpath=$(cd $(dirname "$pkgfile"); pwd -P)/$(basename "$pkgfile")
	cd "$dest"
	$xar -xf  "$fullpath"
	local pkgext=".${pkgfile##*.}"
	if [ "$pkgext" == ".pkg" ]; then
		echo "Extracting Payloads..."
		find . -type f -name "Payload" -exec echo "Extracting {}" \; -exec bash -c 'payload_extractor "$0"' {} \;
		if [ ! "$3" == "skip" ]; then
			read -p "Do you want to remove packed files? (y/n)" -n1 -r
			echo
			if [[ $REPLY =~ ^[Yy]$ ]];then
				echo "Removing Packed Files..."
				find . -type f -name "Payload" -delete
				find . -type f -name "Scripts" -delete
				find . -type f -name "PackageInfo" -delete
				find . -type f -name "Bom" -delete
			fi
		fi
	elif [ "$extension" == ".mpkg" ]; then
		if [ -f "$dest/$(basename "$pkgfile")" ]; then #dummy mpkg in mpkg
			rm "$dest/$(basename "$pkgfile")"
		fi
	fi
	cd "$scriptdir"
	if  [ ! -z $username ] && [ ! "$username" == "" ] && [ ! "$username" == " " ]; then
		chown -R "$user" "$dest"
		chmod -R 666 "$dest"
	fi
}

function compile_xar(){
	xarver="1.5.2"
	if [ ! -f "xar-"$xarver".tar.gz" ]; then
		wget "http://xar.googlecode.com/files/xar-"$xarver".tar.gz"
		if [ ! -f "xar-"$xarver".tar.gz" ]; then
			err_exit "Download failed\n"
		fi
	fi
	if [ -d "xar-"$xarver"" ]; then rm -r "xar-"$xarver""; fi
		tar xvf "xar-"$xarver".tar.gz"
		cd "xar-"$xarver""
		./configure --prefix="$scriptdir/xar_bin"
		make
		if [ ! $? == 0 ]; then
			err_exit "Xar Build Failed\n"
		fi
		make install
	if  [ ! -z $username ] && [ ! "$username" == "" ] && [ ! "$username" == " " ]; then
		chown -R "$user" "xar-"$xarver""
		chmod -R 666 "xar-"$xarver""
	fi
}

function compile_d2i(){
	if [ ! -f "dmg2img-"$dmgimgversion".tar.gz" ]; then
		wget "http://vu1tur.eu.org/tools/dmg2img-"$dmgimgversion".tar.gz"
		if [ ! -f "dmg2img-"$dmgimgversion".tar.gz" ]; then
			err_exit "Download failed\n"
		fi
	fi
	if [ ! -d "dmg2img-"$dmgimgversion"" ]; then rm -r "dmg2img-"$dmgimgversion""; fi
		tar xvf "dmg2img-"$dmgimgversion".tar.gz"
		cd "dmg2img-"$dmgimgversion""
		make
		if [ ! $? == 0 ]; then
			err_exit "dmg2img Build Failed\n"
		else
			$lgreen; echo "Build completed!"; $normal
		fi
		DESTDIR="$scriptdir/dmg2img_bin" make install
	if  [ ! -z $username ] && [ ! "$username" == "" ] && [ ! "$username" == " " ]; then
		chown -R "$user" "dmg2img-"$dmgimgversion""
		chmod -R 666 "dmg2img-"$dmgimgversion""
	fi
	dmg2img="$scriptdir/dmg2img_bin/usr/bin/dmg2img"
}

function usage(){
echo "Osx Installer/Utilities for Linux by SMX"
printf "$0 [dmgfile] [dev]\t\tConverts and install a dmg to a device\n"
printf "$0 [dmgfile] [img file]\t\tConverts and install and create an img file\n"
printf "$0 [dmgfile] [vdi/vmdk/vhd]\tConverts and install and create a virtual hard disk\n"
printf "$0 [img file/vdi/vmdk/vhd]\tOpen the setup management/tweak menu\n"
printf "$0 [pkg/mpkg] [destdir]\t\tExtract a package to destdir\n"
printf "Management menu:\n"
printf "\t-Install/Remove extra kexts\n"
printf "\t-Install/Reinstll chameleon\n"
printf "\t-Install/Reinstall mbr patch\n"
#printf "\t-Apply tweaks/workarounds\n"
printf "\t-Erase the whole setup partition\n"
}
main "$1" "$2" "$3" "$4"
