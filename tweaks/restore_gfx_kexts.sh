#!/bin/bash
tweakname="Restore Graphic Kexts"
if [ ! -d /mnt/osx/target/kext_backup/gfx ]; then
	$lred; echo "Graphic Kexts not removed, can't restore"; $normal
	exit 1
fi

cd /mnt/osx/target/kext_backup/gfx/
for k in *.kext; do
	echo "Restoring $k"
	mv $k /mnt/osx/target/System/Library/Extensions/
done

if [ $(ls -1 /mnt/osx/target/kext_backup/gfx/ | wc -l) == 0 ]; then
	rmdir /mnt/osx/target/kext_backup/gfx/
else
	$lred; echo "Restore failed"; $normal
fi
do_remcache
do_kextperms