#!/bin/bash
dmgimgversion="1.6.5"
xarver="1.6.1"
kconfigver="3.12.0.0"
darling_dmgver="1.0.4"


function check_commands {
	$lyellow; echo "Checking Commands..."
	$normal
	#if [ $commands_checked == 1 ]; then
		#add checks for other commands after the initial check
	#	echo &>/dev/null
	#else
		commands=(
			'grep' 'dd' 'sed'
			'parted' 'awk' 'mkfs.hfsplus'
			'wget' 'dirname' 'basename'
			'parted' 'pidof' 'gunzip'
			'bunzip2' 'cpio' 'unbuffer')
	#fi
	for command in "${commands[@]}"; do
		if ! check_command $command == 0; then
			$normal
			err_exit ""
		fi
		$normal
	done
}

function find_cmd {
	# Command to look for
	cmdvar=$1
	# Preferred search dir
	cmd_dir=$2
	# Full command name (optional)
	cmd=$3

	local cmd_path
	if [ ! -z "${cmd}" ]; then
		cmd_path="${cmd_dir}/${cmd}"
	elif [ ! -z "${cmd_dir}" ]; then
		cmd_path="${cmd_dir}/${cmdvar}"
	else
		cmd_path="$(type -P "${cmdvar}")"
	fi

	# Store the command path in the command-named variable (ex xar -> $xar)
	if [ -e "${cmd_path}" ]; then
		eval ${cmdvar}=${cmd_path}
	else
		unset ${cmdvar}
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

	if [ -z "$command" ]; then
		cmdstat=1
	fi
	$lcyan; printf "$command_name: "
	if [ $cmdstat == 0 ]; then
		$lgreen; printf "Found\n"; $normal
		return 0
	elif [ $cmdstat == 1 ]; then
		$lred; printf "Not Found\n"; $normal
		return 1
	else
		$lightgray; printf "Unknown Error\n"; $normal
		return 2
	fi
}


function docheck_darlingdmg(){
	if [ -z "${mount_hfs}" ]; then
		compile_darlingdmg
	fi
}

function compile_darlingdmg(){
	$lyellow; echo "Compiling darling-dmg..."; $normal
	if [ ! -f "darling-dmg-${darling_dmgver}.tar.gz" ]; then
		if ! wget "https://github.com/darlinghq/darling-dmg/archive/v${darling_dmgver}.tar.gz" -O "darling-dmg-${darling_dmgver}.tar.gz"; then
			err_exit "Download failed\n"
		fi
	fi
	if [ -d "darling-dmg-${darling_dmgver}" ]; then rm -r "darling-dmg-${darling_dmgver}"; fi
		if ! tar xvf "darling-dmg-${darling_dmgver}.tar.gz"; then
			err_exit "Extraction failed\n"
		fi
		mkdir "darling-dmg-${darling_dmgver}/build"
		pushd "darling-dmg-${darling_dmgver}/build" &>/dev/null
		if ! cmake cmake -DCMAKE_INSTALL_PREFIX:PATH="${scriptdir}/bins" ..; then
			err_exit "Configuration Failed!\n"
		fi
		if ! make; then
			err_exit "darling-dmg Build Failed\n"
		fi
		if ! make install; then
			err_exit "darling-dmg Install Failed\n"
		fi
		popd &>/dev/null
		chown "$SUDO_USER":"$SUDO_USER" "${scriptdir}/darling-dmg-${darling_dmgver}.tar.gz"
		chown -R "$SUDO_USER":"$SUDO_USER" "darling-dmg-${darling_dmgver}"
		mount_hfs="${scriptdir}/bins/bin/darling-dmg"
		if [ ! -f "$mount_hfs" ]; then
			err_exit "darling-dmg Build Failed\n"
		fi
}

function docheck_kconfig(){
	if [ -z "${kconfig_mconf}" ]; then
		compile_kconfig
	fi
}

function compile_kconfig(){
	$lyellow; echo "Compiling kconfig..."; $normal
	if [ ! -f "kconfig-frontends-${kconfigver}.tar.xz" ]; then
		if ! wget "http://ymorin.is-a-geek.org/download/kconfig-frontends/kconfig-frontends-${kconfigver}.tar.xz"; then
			err_exit "Download failed\n"
		fi
	fi
	if [ -d "kconfig-frontends-${kconfigver}" ]; then rm -r "kconfig-frontends-${kconfigver}"; fi
		if ! tar xvf "kconfig-frontends-${kconfigver}.tar.xz"; then
			err_exit "Extraction failed\n"
		fi
		pushd "kconfig-frontends-${kconfigver}" &>/dev/null
		./configure --prefix="$scriptdir/bins"
		if ! make; then
			err_exit "Kconfig Build Failed\n"
		fi
		if ! make install; then
			err_exit "Kconfig Install Failed\n"
		fi
		popd &>/dev/null
		chown "$SUDO_USER":"$SUDO_USER" "${scriptdir}/kconfig-frontends-${kconfigver}.tar.xz"
		chown -R "$SUDO_USER":"$SUDO_USER" "${scriptdir}/kconfig-frontends-${kconfigver}"
		kconfig_mconf="${scriptdir}/bins/bin/kconfig-mconf"
		if [ ! -f "$kconfig_mconf" ]; then
			err_exit "Kconfig Build Failed\n"
		fi
}

function docheck_xar(){
	if [ -z "$xar" ]; then
		compile_xar
	else
		local chkxar=$($xar --version 2>&1 | grep -q "libxar.so.1"; echo $?)
		if [ $chkxar == 0 ]; then
			$lyellow; echo "xar is not working. recompiling..."; $normal
			rm -r xar_bin/*
			$lyellow; echo "Recompiling xar..."; $normal
			compile_xar
			local chkxar=$($xar -v 2>&1 | grep -q "libxar.so.1"; echo $?)
			if [ $chkxar == 0 ]; then
				err_exit "xar broken, cannot continue\n"
			fi
		fi
	fi
}

function compile_xar(){
	$lyellow; echo "Compiling xar..."; $normal
	if [ ! -f "xar-"$xarver".tar.gz" ]; then
		if ! wget "https://github.com/downloads/mackyle/xar/xar-${xarver}.tar.gz"; then
			err_exit "Download failed\n"
		fi
	fi
	if [ -d "xar-"$xarver"" ]; then rm -r "xar-"$xarver""; fi
		if ! tar xvf "xar-"$xarver".tar.gz"; then
			err_exit "Extraction failed\n"
		fi
		pushd "xar-${xarver}" &>/dev/null
		./configure --prefix="$scriptdir/bins"
		if ! make; then
			err_exit "Xar Build Failed\n"
		fi
		if ! make install; then
			err_exit "Xar Install Failed\n"
		fi
		popd &>/dev/null
		chown "$SUDO_USER":"$SUDO_USER" "${scriptdir}/xar-${xarver}.tar.gz"
		chown -R "$SUDO_USER":"$SUDO_USER" "${scriptdir}/xar-${xarver}"
		xar="${scriptdir}/bins/bin/xar"
		if [ ! -f "$xar" ]; then
			err_exit "Xar Build Failed\n"
		fi

}

function docheck_pbzx(){
	if [ -z "$pbzx" ]; then
		$lyellow; echo "Compiling pbzx..."; $normal
		if ! gcc -Wall -pedantic "${scriptdir}/pbzx.c" -o "${scriptdir}/bins/bin/pbzx"; then
			err_exit "pbzx Build Failed\n"
		fi
		pbzx="${scriptdir}/bins/bin/pbzx"
	fi
}

function docheck_dmg2img(){
	if [ -z "$dmg2img" ]; then
			$lyellow; echo "Compiling dmg2img..."; $normal
			compile_d2i
	else
		c_d2iver=$($dmg2img 2>&1| grep v | sed -n 1p | awk '{print $2}' | sed 's/v//g')
		if [ ! "$d2iver" == "$dmgimgversion" ] && [ "$dmg2img" == "dmg2img" ]; then
			$lyellow; echo "WARNING! dmg2img is not updated and may cause problems"
			echo "Detected version: "$d2iver""
			echo "Recommanded version: "$dmgimgversion""
			read -p "Compile version "$dmgimgversion"? (y/n)" -n1 -r
			echo; $normal
			if [[ $REPLY =~ ^[Yy]$ ]];then
				$lyellow; echo "Compiling dmg2img..."; $normal
				compile_d2i
			fi
		fi
	fi
}

function compile_d2i(){
	if [ ! -f "dmg2img-"$dmgimgversion".tar.gz" ]; then
		if ! wget "http://vu1tur.eu.org/tools/dmg2img-"$dmgimgversion".tar.gz"; then
			err_exit "Download failed\n"
		fi
	fi
	if [ ! -d "dmg2img-"$dmgimgversion"" ]; then
		rm -r "dmg2img-"$dmgimgversion""
	fi
	if ! tar xvf "dmg2img-"$dmgimgversion".tar.gz"; then
		err_exit "Extraction failed\n"
	fi
	pushd "dmg2img-${dmgimgversion}" &>/dev/null
	if ! make; then
		$lred; echo "dmg2img Build Failed"; $normal
		$lyellow; echo -e "Make sure you have installed the necessary build deps\nOn debian/ubuntu"; $normal
		$white; echo "sudo apt-get build-dep dmg2img"; $normal
		err_exit ""
	fi
	if ! DESTDIR="${scriptdir}/bins" make install; then
		err_exit "dmg2img Install Failed\n"
	fi
	cp -Ra ${scriptdir}/bins/usr/* "${scriptdir}/bins/"
	rm -rf ${scriptdir}/bins/usr
	chown "$SUDO_USER":"$SUDO_USER" "${scriptdir}/dmg2img-${dmgimgversion}.tar.gz"
	chown -R "$SUDO_USER":"$SUDO_USER" "${scriptdir}/dmg2img-${dmgimgversion}"
	dmg2img="${scriptdir}/bins/bin/dmg2img"
	if [ ! -f "$dmg2img" ]; then
		err_exit "dmg2img Build Failed\n"
	fi
}
