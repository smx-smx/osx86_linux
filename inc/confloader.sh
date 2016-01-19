#!/bin/bash
function load_config(){
  if [ ! -f "${scriptdir}/.config" ]; then
    $lred
    echo "osx86_linux not configured!"
    echo "Run Kconfig first and try again"
    $normal
    err_exit ""
  fi
  eval $(cat "${scriptdir}/.config" | grep -v "^#")
}

function is_on(){
  local option="CONFIG_$1"
  [ "${!option}" == "y" ] && return 0 #0 -> success (it's on)
  return 1 #1 -> failure (it's not on)
}
