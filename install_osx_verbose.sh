#!/bin/bash
source inc/[0-9]*colors.sh
source inc/[0-9]*utils.sh

export G_REALLY_VERBOSE=1

if [ ! -f "install_osx.sh" ]; then
	err_exit "Can't find install_osx.sh\n"
fi

./install_osx.sh "$@"
exit $?
