osx86_linux
===========

osx86 media for Linux
Aimed at people who want to try OS X, but don't have a real MAC to 
prepare the usb installer, or have a CPU that doesn't support 
Virtualization

This script creates an osx86 install media starting from a dmg file.

TODO: Beautify the code. Remove ugly parts

Should work with:
 OSX 10.6, 10.7, 10.8, 10.9

Required files:
chameleon:
 boot
 boot0
 boot1h

extra_kexts:
 FakeSMC.kext
 <any other kext> (NullCPUPowerManagement, ps2 controller, ...)

osinstall_mbr:
 OSInstall
 OSInstall.mpkg

see ./install_osx.sh -h for usage

This script uses:
 dmg2img (version 1.6.5 strongly recommended)
 qemu-nbd
 mkfs.hfsplus
