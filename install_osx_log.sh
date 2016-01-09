#!/bin/bash
lred='printf \033[01;31m'
export really_verbose=0
function initlog(){
	export logfile=`date +%d-%b-%y_%H%M%S`".log"
	if [ -f "$scriptdir/$logfile" ]; then rm "$scriptdir/$logfile"; fi
	touch "$logfile"
}

function err_exit() {
	$lred; printf "$1"; $normal
	exit 1
}

initlog
if [ ! -f "install_osx.sh" ]; then err_exit "Can't find install_osx.sh"; fi
./install_osx.sh "$@" 2>&1 | tee "$logfile"
if [ "$SUDO_USER"=="" ]; then SUDO_USER="root"; fi

####https://github.com/pixelb/scripts/blob/master/scripts/ansi2html.sh####
htmlfile=$(echo "$logfile" | sed 's/\.log/\.html/g')
cat "$logfile" | ./ansi2html.sh --bg=dark > "$htmlfile"
rm "$logfile"
chown "$SUDO_USER" "$htmlfile"
chmod 666 "$htmlfile"
exit 0
