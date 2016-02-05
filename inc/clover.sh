#!/bin/bash
function do_clover(){
	local target_mbr
	local target_pbr
	if [ $virtualdev -eq 1 ]; then
		target_mbr="/dev/nbd0"
		target_pbr="${target_mbr}p1"
	else
		target_mbr="${dev}"
		target_pbr="${dev}1"
	fi

	$lyellow; echo "Installing clover..."; $normal
	if [ -f "${scriptdir}/clover/boot0ss" ]; then
		$yellow; echo "Flashing Master boot record..."; $normal
		dd if="${scriptdir}/clover/boot0ss" of="${target_mbr}"
	fi
	if [ -f "${scriptdir}/clover/boot1f32alt" ]; then
		$yellow; echo "Flashing Partition boot record..."; $normal
		dd if="${target_pbr}" count=1 bs=512 of="${scriptdir}/tmp/origbs"
		cp $verbose "${scriptdir}/clover/boot1f32alt" "${scriptdir}/tmp/newbs"
		dd if="${scriptdir}/tmp/origbs" of="${scriptdir}/tmp/newbs" skip=3 seek=3 bs=1 count=87 conv=notrunc
		dd if="${scriptdir}/tmp/newbs" of="${target_pbr}" bs=512 count=1
	fi
}
