#!/bin/bash
tweakname="Remove ApplePolicyControl.kext"
if [ ! -d /mnt/osx/target/kext_backup/gfx ]; then
	mkdir -p /mnt/osx/target/kext_backup
fi

if [ -f /mnt/osx/target/System/Library/Extensions/AppleGraphicsControl.kext/Contents/PlugIns/ApplePolicyControl.kext ]; then
	echo "Removing ApplePolicyControl.kext.."
	mv /mnt/osx/target/System/Library/Extensions/AppleGraphicsControl.kext/Contents/PlugIns/ApplePolicyControl.kext /mnt/osx/target/kext_backup/
else
	echo "ApplePolicyControl.kext already removed"
fi

