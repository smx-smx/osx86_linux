#!/bin/bash
dmgimgversion="1.6.5"
xarver="1.5.2"
kconfigver="3.12.0.0"

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
		./configure --prefix="$scriptdir/kconfig_bin"
		if ! make; then
			err_exit "Kconfig Build Failed\n"
		fi
		if ! make install; then
			err_exit "Kconfig Install Failed\n"
		fi
		popd &>/dev/null
		chown "$SUDO_USER":"$SUDO_USER" "$scriptdir/xar-"$xarver".tar.gz"
		chown -R "$SUDO_USER":"$SUDO_USER" "$scriptdir/xar-"$xarver""
		chown -R "$SUDO_USER":"$SUDO_USER" "$scriptdir/xar_bin"
		kconfig_mconf="${scriptdir}/kconfig_bin/bin/kconfig_mconf"
		if [ ! -f "$xar" ]; then
			err_exit "KConfig Build Failed\n"
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
		if ! wget "http://xar.googlecode.com/files/xar-"$xarver".tar.gz"; then
			err_exit "Download failed\n"
		fi
	fi
	if [ -d "xar-"$xarver"" ]; then rm -r "xar-"$xarver""; fi
		if ! tar xvf "xar-"$xarver".tar.gz"; then
			err_exit "Extraction failed\n"
		fi
		pushd "xar-${xarver}" &>/dev/null
		./configure --prefix="$scriptdir/xar_bin"
		if ! make; then
			err_exit "Xar Build Failed\n"
		fi
		if ! make install; then
			err_exit "Xar Install Failed\n"
		fi
		popd &>/dev/null
		chown "$SUDO_USER":"$SUDO_USER" "$scriptdir/xar-"$xarver".tar.gz"
		chown -R "$SUDO_USER":"$SUDO_USER" "$scriptdir/xar-"$xarver""
		chown -R "$SUDO_USER":"$SUDO_USER" "$scriptdir/xar_bin"
		xar="${scriptdir}/xar_bin/bin/xar"
		if [ ! -f "$xar" ]; then
			err_exit "Xar Build Failed\n"
		fi

}

function docheck_pbzx(){
	if [ -z "$pbzx" ]; then
		$lyellow; echo "Compiling pbzx..."; $normal
		if ! gcc -Wall -pedantic "${scriptdir}/pbzx.c" -o "${scriptdir}/pbzx"; then
			err_exit "pbzx Build Failed\n"
		fi
		pbzx="${scriptdir}/pbzx"
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
	if ! DESTDIR="$scriptdir/dmg2img_bin" make install; then
		err_exit "dmg2img Install Failed\n"
	fi
	chown "$SUDO_USER":"$SUDO_USER" "$scriptdir/dmg2img-"$dmgimgversion".tar.gz"
	chown -R "$SUDO_USER":"$SUDO_USER" "$scriptdir/dmg2img-"$dmgimgversion""
	chown -R "$SUDO_USER":"$SUDO_USER" "$scriptdir/dmg2img_bin"
	dmg2img="$scriptdir/dmg2img_bin/usr/bin/dmg2img"
	if [ ! -f "$dmg2img" ]; then
		err_exit "dmg2img Build Failed\n"
	fi
}
