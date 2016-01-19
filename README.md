#osx86_linux

osx86_linux is a script aimed at people who want to try OS X (hackintosh, but also vanilla pendrive preparation will be possible in the future), but don't have a real MAC to prepare the usb installer, or have a CPU that doesn't support 
virtualization.

This script creates an osx86 installer starting from a dmg file (InstallESD or Install DVD).

Should work with OS X Snow leopard (10.6) and above
 
TODO:
- GPT support
- UEFI support
- Clover support
- Vanilla installer support (via boot.efi)
- Some form of dialog / UI
- Config file
- Use FUSE to access the DMG directly instead of dmg2img
- Modularize more parts of the main script
- Cleanup old code

### Dependencies
`apt-get install build-essential libbz2-dev libxml2-dev tput qemu-utils hfsprogs dialog`
##### dmg2img
`apt-get build-dep dmg2img`
##### kconfig
`apt-get install gperf libncurses5-dev`

For GTK Configuration support

`apt-get install libgtk2.0-dev libglade2-dev`

For QT Configuration support

`apt-get install libqt4-dev`

##### darling-dmg
`apt-get install cmake libfuse-dev libssl-dev libicu-dev zlib1g-dev libbz2-dev`

---------------------------

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
