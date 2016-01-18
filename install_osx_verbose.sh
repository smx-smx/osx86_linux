#!/bin/bash
source inc/colors.sh
source inc/utils.sh

export really_verbose=1

if [ ! -f "install_osx.sh" ]; then
	err_exit "Can't find install_osx.sh\n"
fi

./install_osx.sh "$@"
exit $?
