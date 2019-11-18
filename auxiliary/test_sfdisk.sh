#!/bin/bash
ARCH=x86_64
block_size=512
mega="$(echo '2^20' | bc)"
readonly partition_size_1_megs=10
readonly partition_size_1=$(($partition_size_1_megs * $mega))

readonly partition_size_2_megs=10
partition_size_2=$(($partition_size_2_megs * $mega))

readonly partition_size_3_megs=10
partition_size_3=$(($partition_size_3_megs * $mega))

echo "Create GUID Partition Table (GPT)"
guid_root_x86_64="4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709"
guid_root_aarch64="B921B045-1DF0-41C3-AF44-4C6F280D3FAE"
guid_root=$guid_root_x86_64
[ "$ARCH" == "aarch64" ] && guid_root=$guid_root_aarch64
guid_linux_data="0FC63DAF-8483-4772-8E79-3D69D8477DE4"
guid_efi_system="C12A7328-F81F-11D2-BA4B-00A0C93EC93B"

block_round=$((2048 * $block_size))
partition_start1=$((2048 * $block_size))
partition_start2=$(($partition_start1 + $(echo $partition_size_1 | jq -R "tonumber/$block_round|ceil*$block_round")))
partition_start3=$(($partition_start2 + $(echo $partition_size_2 | jq -R "tonumber/$block_round|ceil*$block_round")))
partition_start4=$(($partition_start3 + $(echo $partition_size_3 | jq -R "tonumber/$block_round|ceil*$block_round")))
COUNT=$(( ($partition_start4 + $partition_start1)/1024 )) # Add size of GTP header at the end

dd if=/dev/zero of=test.img bs=1024 count=$COUNT conv=fsync
printf "
	label: gpt
	type=$guid_efi_system, size=$(($partition_size_1/$block_size)), bootable, uuid=65AD2B33-BD5A-45FA-8AB1-1B76AE295D3F, name='Boot'
	type=$guid_root, size=$(($partition_size_2/$block_size)), uuid=5B8B1CF4-A735-4256-892E-E3089283E71F, name='Root'
	type=$guid_linux_data, size=$(($partition_size_3/$block_size)), uuid=2BB397B4-67A1-437D-9581-A84219DBA178, name='Data'
	" | sfdisk test.img
