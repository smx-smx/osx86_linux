#!/bin/bash
tweakname="Remove Graphic Kexts"
if [ ! -d /mnt/osx/target/kext_backup/gfx ]; then
	mkdir -p /mnt/osx/target/kext_backup/gfx
fi

cd /mnt/osx/target/System/Library/Extensions
kexts=$(find . -type d -name "AppleIntelHD*.kext" -or -name "AppleIntelSNB*.kext" -or -name "AMDRadeon*.kext" -or -name "ATI*.kext"	-or -name "AMD*.kext"	-or -name "GeForce*.kext" -or -name "NVDA*.kext")
for kext in $kexts; do
	echo "Removing $kext"
	mv "$kext" /mnt/osx/target/kext_backup/gfx/
done

do_remcache
