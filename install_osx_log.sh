#!/bin/bash
source inc/[0-9]*colors.sh
source inc/[0-9]*utils.sh

export really_verbose=0
export log_mode=1

function initlog(){
	logfile=`date +%d-%b-%y_%H%M%S`".log"
	if [ -f "${scriptdir}/${logfile}" ]; then
		rm "${scriptdir}/${logfile}"
	fi
	touch "$logfile"
}

initlog
if [ ! -f "install_osx.sh" ]; then
	err_exit "Can't find install_osx.sh"
fi

./install_osx.sh "$@" 2>&1 | tee "$logfile"
result=$?

####https://github.com/pixelb/scripts/blob/master/scripts/ansi2html.sh####
htmlfile=$(echo "$logfile" | sed 's/\.log/\.html/g')
cat "$logfile" | ./ansi2html.sh --bg=dark > "$htmlfile"
rm "$logfile"
chown "$SUDO_USER" "$htmlfile"
chmod 666 "$htmlfile"
exit $result
