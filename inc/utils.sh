#!/bin/bash
function trim(){
	local text="$*"
	echo -ne "${text//[$'\t\r\n']}"
}

function pause() {
	if [ "$1" == "" ]; then
		$white; read -p "Press [enter] to continue"; $normal
	else
		$white; read -p "$*"; $normal
	fi
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

function isEmpty() {
	local dir=$1
	if [ $(( $(ls -a1 "${dir}" | wc -l) - 2)) -eq 0 ]; then
		return 0 #good, it's empty
	else
		return 1 #bad, not empty
	fi
}

function isRO(){
	local mountdev="$1"
	local dev_major=$(stat -c "%t" "${mountdev}")
	local dev_minor=$(stat -c "%T" "${mountdev}")
	if [ ! -f "/sys/dev/block/${dev_major}:${dev_minor}/ro" ]; then
		err_exit "Can't get readonly flag\n"
	fi
	local isRO=$(cat /sys/dev/block/${dev_major}:${dev_minor}/ro)
	if [ ${isRO} -eq 1 ]; then
		err_exit "${mountdev} is mounted in R/O mode!\n"
	fi
	return ${isRO}
}
