#!/bin/bash
function trim(){
	local text="$*"
	echo -ne "${text//[$'\b\t\r\n']}"
}

function negate(){
	[[ $1 -gt 0 ]] && return 0 || return 1;
}

function pause() {
	if [ "$1" == "" ]; then
		$white; read -p "Press [enter] to continue"; $normal
	else
		$white; read -p "$*"; $normal
	fi
}

function git_getrev(){
	echo $(git log --pretty=oneline 2>/dev/null | wc -l)
}

function md5_compare(){
	local file1="$1"
	local file2="$2"

	local chksum1="$(md5sum "${file1}" | awk '{print $1}')"
	if [ ! ${PIPESTATUS[0]} -eq 0 ]; then
		#error
		return $?
	fi
	local chksum2="$(md5sum "${file2}" | awk '{print $1}')"
	if [ ! ${PIPESTATUS[0]} -eq 0 ]; then
		#error
		return $?
	fi

	[ "${chksum1}" == "${chksum2}" ] && return 0
	return 1
}

function read_yn(){
	local prompt="$*"
	read -p "${prompt} (y/n)" -n2 -r
	if [[ $REPLY =~ ^[Yy]$ ]];then
		return 0 #ok
	fi

	# Anything else is bad
	return 1
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
	local dir="$1"
	[ "$(ls -A "${dir}")" ] && return 1 || return 0 #error on not empty
}

function str_contains(){
	local string="$1"
	local search="$2"
	if [[ $string == *"${search}"* ]]; then
		return 0
	fi
	return 1
}

function get_mime(){
	local file="$1"
	local out_mime="$2"
	local out_charset="$3"
	
	local file_out="$(file -ib "${file}" | sed 's/$/;/g')" #append ; to end of line
	local mime charset
	read mime charset <<< "${file_out}"
	charset="$(echo "${charset}" | cut -d '=' -f2)"

	eval ${out_mime}="${mime}"
	eval ${out_charset}="${charset}"
}