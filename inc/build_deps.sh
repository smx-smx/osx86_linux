#!/bin/bash

dmgimgversion="1.6.5"
xarver="1.5.2"
kconfigver="3.12.0.0"

function docheck_kconfig(){
	if [ -z "$kconfig_mconf" ]; then
		compile_kconfig
	fi
}

function compile_kconfig(){
	:
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
		wget "http://xar.googlecode.com/files/xar-"$xarver".tar.gz"
		if [ ! -f "xar-"$xarver".tar.gz" ]; then
			err_exit "Download failed\n"
		fi
	fi
	if [ -d "xar-"$xarver"" ]; then rm -r "xar-"$xarver""; fi
		tar xvf "xar-"$xarver".tar.gz"
		pushd "xar-${xarver}" &>/dev/null
		./configure --prefix="$scriptdir/xar_bin"
		make
		if [ ! $? == 0 ]; then
			err_exit "Xar Build Failed\n"
		fi
		make install
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
		gcc -Wall -pedantic "${scriptdir}/pbzx.c" -o "${scriptdir}/pbzx"
		if [ ! $? -eq 0 ]; then
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
			$lred; echo "dmg2img Build Failed"; $normal
			$lyellow; echo -e "Make sure you have installed the necessary build deps\nOn debian/ubuntu"; $normal
			$white; echo "sudo apt-get build-dep dmg2img"; $normal
			err_exit ""
		else
			$lgreen; echo "Build completed!"; $normal
		fi
	DESTDIR="$scriptdir/dmg2img_bin" make install
	chown "$SUDO_USER":"$SUDO_USER" "$scriptdir/dmg2img-"$dmgimgversion".tar.gz"
	chown -R "$SUDO_USER":"$SUDO_USER" "$scriptdir/dmg2img-"$dmgimgversion""
	chown -R "$SUDO_USER":"$SUDO_USER" "$scriptdir/dmg2img_bin"
	dmg2img="$scriptdir/dmg2img_bin/usr/bin/dmg2img"
	if [ ! -f "$dmg2img" ]; then
		err_exit "dmg2img Build Failed\n"
	fi
}
