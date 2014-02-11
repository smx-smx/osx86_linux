#!/bin/bash
lred='printf \033[01;31m'
export really_verbose=0

function err_exit() {
	$lred; printf "$1"; $normal
	exit 1
}

if [ ! -f "install_osx.sh" ]; then err_exit "Can't find install_osx.sh"; fi
./install_osx.sh "$@"
exit 0
