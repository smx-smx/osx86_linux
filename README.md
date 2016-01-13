#osx86_linux

osx86_linux is a script aimed at people who want to try OS X (hackintosh, but also vanilla pendrive preparation will be possible in the future), but don't have a real MAC to prepare the usb installer, or have a CPU that doesn't support 
virtualization.

This script creates an osx86 installer starting from a dmg file (InstallESD or Install DVD).

Should work with:
 OSX 10.6, 10.7, 10.8, 10.9

###Dependencies
`apt-get install build-essential libbz2-dev libxml2-dev tput qemu-utils hfsprogs`

For Virtual HD support:

`apt-get install virtualbox`

For chameleon support:
- chameleon/boot
- chameleon/boot0
- chameleon/boot1h

For additional kexts:
- extra_kexts/FakeSMC.kext
- \<any other kext\> (NullCPUPowerManagement, ps2 controller, ...)

For MBR Patch:
- osinstall_mbr/OSInstall
- osinstall_mbr/OSInstall.mpkg

Custom SMBios:

Place smbios.plist in script directory

see ./install_osx.sh -h for usage


I AM NOT RESPONSIBLE FOR ANY DAMAGE THE USE OF THIS SCRIPT MAY CAUSE.
