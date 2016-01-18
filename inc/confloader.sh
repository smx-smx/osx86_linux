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
