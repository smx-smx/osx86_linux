#!/bin/bash
function mediamenu(){
	mediamenu=1
	if [ $virtualdev == 1 ]; then
		if [ $nbd0_mapped -eq 0 ]; then
			$white; echo "Mapping ${in_arg}..."; $normal
			if ! qemu_map "nbd0" "$in_arg"; then
				err_exit "Can't map ${in_arg}\n"
			fi
			dev_target="/dev/nbd0"
      if [ $virtualdev -eq 1 ]; then
        dev_target="${dev_target}p1"
      else
        dev_target="${dev_target}1"
      fi
		fi
		if [ ! -b "/dev/nbd0p1" ]; then
			err_exit "Corrupted image\n"
		fi
	fi

	if ! grep -q "/mnt/osx/target" /proc/mounts; then
		$yellow; echo "Mounting..."; $normal
		if ! mount_part "$dev_target" "target" "silent"; then
			err_exit "Cannot mount target\n"
		else
			$lgreen; echo "Target Mounted"; $normal
		fi
		if [ ! -d /mnt/osx/target/Extra ]; then
			mkdir -p /mnt/osx/target/Extra/Extensions
		fi
		detect_osx_version
	fi
	echo "Working on ${dev_target}"
	echo "Choose an operation..."
	echo "1  - Manage kexts"
	echo "2  - Manage chameleon Modules"
	echo "3  - Manage kernels"
	echo "4  - Reinstall / Update chameleon"
	echo "5  - Reinstall stock kernel"
	echo "6  - Install / Reinstall MBR Patch"
	echo "7  - Install / Reinstall Custom DSDT"
	echo "8  - Install / Reinstall SMBios"
	echo "9  - Erase Setup"
	echo "10 - Delete Kext Cache"
	echo "11 - Tweaks Menu"
	echo "0  - Exit"
	$white; printf "Choose an option: "; read choice; $normal
	case "$choice" in
		0)
			err_exit ""
			;;
		1)
			clear
			kextmenu
			mediamenu
			;;
		2)
			clear
			chammodmenu
			mediamenu
			;;
		3)
			clear
			kernelmenu
			mediamenu
			;;
		4)
			docheck_chameleon
			mediamenu
			;;
		5)
			do_kernel "target"
			mediamenu
			;;
		6)
			docheck_mbr
			pause; clear
			mediamenu
			;;
		7)
			docheck_dsdt
			pause; clear
			mediamenu
			;;
		8)
			docheck_smbios
			pause; clear
			mediamenu
			;;
		9)
			do_cleanup
			if [ $virtualdev == 1 ]; then
				$lred; echo "WARNING: You are about to delete ${in_arg} content!"
				read -p "Are you really sure you want to continue? (y/n)" -n1 -r
				echo; $normal
				if [[ $REPLY =~ ^[Nn]$ ]];then
					err_exit ""
				fi
				rm "${in_arg}"
				$lgreen; echo "$(basename $in_arg) succesfully deleted" ; $normal
				#else
				#	echo "Can't delete image"
			else
				$lred; echo "WARNING: You are about to erase ${dev_target}!"
				read -p "Are you really sure you want to continue? (y/n)" -n1 -r
				echo; $normal
				if [[ $REPLY =~ ^[Nn]$ ]];then
					err_exit ""
				fi
					dd if=/dev/zero of="${dev_target}" bs=512 count=1
					$lgreen: echo echo "${dev_target} succesfully erased"; $normal
			fi
			err_exit ""
			;;
		10)
			do_remcache
			mediamenu
			;;
		11)
			clear
			tweakmenu
			mediamenu
			;;
		*)
			pause "Invalid option, press [enter] to try again"
			clear
			mediamenu
	esac
}

function fileChooser(){
  local dir="$1"
  local ext="$2"
  local type="$3"
  local dirtype="$(basename ${dir})"

  local files=($(find "${dir}" -maxdepth 1 -type ${type} -not -name .gitignore -name "${ext}"))
  if [ ${#files[@]} -eq 0 ]; then
    $lred; echo "No option available"; $normal
    pause "Press [enter] to return to menu"
		mediamenu
  fi

  $white; echo "0 - Return to main menu"; $normal

  local install_dir

  case $dir in
    */kernels)
      install_dir="/mnt/osx/target";
      ;;
    */extra_kexts)
      install_dir="/mnt/osx/target/Extra/Extensions"
      ;;
    */chameleon/Modules)
      install_dir="/mnt/osx/target/Extra/Modules"
      ;;
  esac

  for i in ${!files[@]}; do
    case $dir in
      */tweaks)
        local name=$(grep tweakname= ${files[$i]} | grep -o "=.*" | sed 's|[="]||g')
        echo $((i + 1)) - ${name}
        ;;
      *)
        local bname="$(basename ${files[$i]})"
        if [ -${type} "${install_dir}/${bname}" ]; then
          printf "[*]\t$((i + 1)) - ${bname}\n"
        else
          printf "[ ]\t$((i + 1)) - ${bname}\n"
        fi
        ;;
    esac
  done

  $white; printf "Choose an option: "; $normal
	read choice
  if [ -z $choice ] || [ $choice -lt 0 ] || [ $choice -gt ${#files[@]} ]; then
    pause "Invalid option, press [enter] to try again"
		clear
    fileChooser
  elif [ $choice -eq 0 ]; then
    clear
    mediamenu
  else
    local option=${files[$((choice-1))]}
    case $dirtype in
      */tweaks)
        $yellow; echo "Applying ${option}..."; $normal
        bash "${option}"
        ;;
      *)
        local bname="$(basename ${option})"
        if [ ! -d "${install_dir}" ]; then
          mkdir -p "${install_dir}"
        fi
        if [ -${type} "${install_dir}/${bname}" ]; then
    			$yellow; echo "Removing ${bname}..."; $normal
    			rm -R "${install_dir}/${bname}"
    		else
    			$yellow; echo "Installing ${bname}..."; $normal
    			cp -R "${option}" "${install_dir}"
    			chown -R 0:0 "${install_dir}/${bname}"
    			chmod -R 755 "${install_dir}/${bname}"
    		fi
        ;;
    esac
  fi
  $lgreen; echo "Done!"; $normal
  pause
  clear
  fileChooser "${dir}" "${ext}" "${type}"
}

function tweakmenu(){
  fileChooser "${scriptdir}/tweaks" "*.sh" "f"
}

function kextmenu(){
  fileChooser "${scriptdir}/extra_kexts" "*.kext" "d"
}

function chammodmenu(){
  fileChooser "${scriptdir}/chameleon/Modules" "*.dylib" "f"
}

function kernelmenu(){
  fileChooser "${scriptdir}/kernels" "*" "f"
}
