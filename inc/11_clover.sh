#!/bin/bash
function do_clover_mbr(){
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

function do_clover_gpt(){
	#cp <something> to /mnt/osx/esp
	:
}

function do_clover(){
	$lyellow; echo "Installing clover..."; $normal
	if is_on PART_MBR; then
		#Not verified yet
		#do_clover_mbr
		: #bash nop
	elif is_on PART_GPT; then
		do_clover_gpt
	fi
}
