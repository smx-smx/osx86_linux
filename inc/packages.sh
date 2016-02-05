#!/bin/bash
function payload_extractor(){
	payload="$1"
	local fmt=$(file -b --mime-type "${payload}")
	local cpio="cpio -i --no-absolute-filenames"
	local unarch

	local gunzip
	local bunzip2

	if [[ "$fmt" =~ "gzip" ]]; then
		find_cmd "gunzip" ""
		$gunzip -dc "${payload}" | ${cpio}
	elif [[ "$fmt" =~ "bzip2" ]]; then
		find_cmd "bunzip2" ""
		$bunzip2 -dc "${payload}" | ${cpio}
	else
		$pbzx "${payload}" | xz -dc | ${cpio}
	fi
	if [ ! $? == 0 ]; then
		$lred; echo "WARNING: "${payload}" Extraction failed"; $normal
	fi
}

function extract_pkg(){
	pkgfile="$1"
	dest="$2"
	prompt="$3" #"skip" to avoid it

	if [ -z $xar ]; then
		err_exit "Xar missing or not enabled, cannot continue\n"
	fi

	local srcpath
	local dstpath

	# if it's a relative path
	if [[ ! "$pkgfile" = /* ]]; then
		srcpath="$(pwd -P)/${pkgfile}"
	else
		srcpath="${pkgfile}"
	fi
	# if it's a relative path
	if [[ ! "$dest" = /* ]]; then
		dstpath="$(pwd -P)/${dest}"
	else
		dstpath="${dest}"
	fi

	if [ ! -d "$dstpath" ] && [ ! -e "$dstpath" ]; then
		mkdir -p "$dstpath"
	fi

	$yellow; echo "Extracting ${pkgfile} to ${dest}"; $normal

	pushd "${dstpath}" &>/dev/null
	if ! $xar -xf "${srcpath}"; then
		popd &>/dev/null
		$lred; echo "${pkgfile} extraction failed!"
		return 1
	fi

	local pkgext=".${pkgfile##*.}"
	$lyellow; echo "Extracting Payloads..."; $normal
	find . -type f -name "Payload" -print0 | while read -r -d '' payload; do
		echo "Extracting "${payload}"..."
		payload_extractor "${payload}"
	done
	popd &>/dev/null

	if [ ${EUID} -eq 0 ]; then
		chown -R "$SUDO_USER":"$SUDO_USER" "${dstpath}"
	fi
	find "${dstpath}" -type d -exec chmod 755 {} \;
	find "${dstpath}" -type f -exec chmod 666 {} \;

	if [ ! "$prompt" == "skip" ]; then
		read -p "Do you want to remove temporary packed payloads? (y/n)" -n1 -r
		echo
		if [[ $REPLY =~ ^[Yy]$ ]] || [ "$pkg_keep_payloads" == "false" ];then
			echo "Removing Packed Files..."
			find ${dstpath} -type f -name "Payload" -delete
			find ${dstpath} -type f -name "Scripts" -delete
			find ${dstpath} -type f -name "PackageInfo" -delete
			find ${dstpath} -type f -name "Bom" -delete
		fi
	fi

	return 0
}
