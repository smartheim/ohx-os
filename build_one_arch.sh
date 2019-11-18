#!/bin/bash

# License: MIT
# David Graeff <david.graeff@web.de> - 2019

# Create a "void linux" image and compressed image file with
# kernel/EFI FAT partition, ext2 root file system and ext4 data partion.
# Provisioned with OHX services and preinstalled container images. No root required.

# Usage: ./build_one_arch.sh MACHINE ARCH, with ARCH being x86_64,armv7l,aarch64. MACHINE: uefi or void supported SOC
# Example usage: ./build_one_arch.sh uefi aarch64

# It would be perfect to use squashfs for the root partition, but we can't without an initial ramdisk.
# The RPI kernel for example doesn't support squashfs as rootfs.
# cramfs would be an option but we have files larger than 16MB (docker bins + icu).
# For reference and maybe future use:
# mksquashfs "$root_dir_2" "$partition_file_2"
# partition_size_2=$(wc -c "$partition_file_2" | cut -f1 -d " ")


MACHINE="$1"
ARCH="$2"
readonly rootpwd=ohxsmarthome

[ -z "$MACHINE" ] && echo "You must set MACHINE, for exmple to 'rpi3'" && exit 1
[ -z "$ARCH" ] && echo "You must set ARCH, for exmple to 'aarch64'" && exit 1

trap "killall partfs > /dev/null; rm -rf tmp/ > /dev/null; exit 1" TERM EXIT

# Work directory is "voidlinux"
mkdir -p voidlinux
cd voidlinux

# Normalize. Void calls those architectures differently than docker or grub
DOCKER_ARCH=$ARCH
GRUB_ARCH=$ARCH
[ "$ARCH" = "armv7l" ] && DOCKER_ARCH=armhf
[ "$ARCH" = "aarch64" ] && GRUB_ARCH=arm64

# Constants

# SOCs require platform rootfs, uefi systems require standard rootfs 
case "$MACHINE" in
	"uefi")
		readonly rootfsbase="$repository/live/$voidversion/void-$ARCH-musl-ROOTFS-$voidversion.tar.xz"
		;;
	*)
		readonly rootfsbase="$repository/live/$voidversion/void-$MACHINE-musl-PLATFORMFS-$voidversion.tar.xz"
esac

readonly repository="https://alpha.de.repo.voidlinux.org"
readonly voidversion="20191109"
readonly rootfs_file="void-$MACHINE-$ARCH-root.tar.xz"
readonly img_file="ohx-$MACHINE-$ARCH.img"
readonly dockerfile="docker-19.03.4.tgz"

readonly mega="$(echo '2^20' | bc)"

readonly root_dir_1=$(realpath "boot")
readonly partition_file_1=$(realpath "part1.fat")

readonly root_dir_2=$(realpath "rootfilesystem")
readonly partition_file_2=$(realpath "part2.ext")

readonly root_dir_3=$(realpath "ohxfs")
readonly partition_file_3=$(realpath "part3.ext")

readonly bs=1024
readonly block_size=512

# GPT specific for x86_64 and aarch64 uefi systems
readonly gpt_uuid_boot="65AD2B33-BD5A-45FA-8AB1-1B76AE295D3F"
readonly gpt_uuid_data="2BB397B4-67A1-437D-9581-A84219DBA178"
readonly guid_root_x86_64="4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709"
readonly guid_root_aarch64="B921B045-1DF0-41C3-AF44-4C6F280D3FAE"
readonly guid_linux_data="0FC63DAF-8483-4772-8E79-3D69D8477DE4"
readonly guid_efi_system="C12A7328-F81F-11D2-BA4B-00A0C93EC93B"


case "$ARCH" in
	"armv7l")
		readonly pkg_docker_engine="https://download.docker.com/linux/static/stable/armhf/$dockerfile"
		readonly containers=( "portainer/portainer:linux-arm" )
		readonly pkgs=( "avahi" "NetworkManager" )
		readonly repo_suffix="musl"
		;;
		
	"aarch64")
		readonly pkg_docker_engine="https://download.docker.com/linux/static/stable/aarch64/$dockerfile"
		readonly containers=( "portainer/portainer:linux-arm64" )
		readonly pkgs=( "avahi" "NetworkManager" )
		readonly repo_suffix="aarch64"
		;;
		
	"x86_64")
		readonly pkg_docker_engine="https://download.docker.com/linux/static/stable/x86_64/$dockerfile"
		readonly containers=( "portainer/portainer:latest" )
		readonly pkgs=( "avahi" "NetworkManager" )
		readonly repo_suffix="musl"
		;;
	*)
		err "Unknown architecture $ARCH"
esac


prerequirements() {
    need_cmd mkdir
    need_cmd dd
    need_cmd printf
    need_cmd sfdisk
    need_cmd wget
	need_cmd unshare
	need_cmd docker
	need_cmd mkpasswd
    need_cmd mkfs.fat
    need_cmd tput
    need_cmd mcopy "GNU mtools"
    need_cmd mke2fs "e2fsprogs"
    
    if [ "$machine" == "uefi" ]; then
		need_cmd grub2-mkconfig
		need_cmd grub2-install
    fi
    
    # For container provisioning with overlayfs we require the kernel module "overlay"
    [ "$(cat /proc/modules|grep overlay|wc -l)" = "0" ] && \
		err "Require overlay kernel module to be loaded: sudo modprobe overlay"
    
    # The helper image is a DIND (docker in docker) to create the shipped /var/lib/docker filestructure
    # and provision some containers as overlay2 images.
    say "Build docker provisioning helper"
    local has_images=$(docker images|grep docker_run|wc -l)
    [ "$has_images" != "1" ] && ensure ./container_helpers/build_containers.sh
    
    # Partfs is used to user mount an .img file
    [ ! -f "./partfs" ] && say "Build partfs" && ensure gcc -D_FILE_OFFSET_BITS=64 -o partfs ../res/partfs/partfs.c -lfdisk -lfuse
    
	[ ! -d $root_dir_1 ] && ensure mkdir "$root_dir_1"
	[ ! -d $root_dir_2 ] && ensure mkdir "$root_dir_2"
	[ ! -d $root_dir_3 ] && ensure mkdir "$root_dir_3"
	/bin/rm -rf $root_dir_1/* > /dev/null
	/bin/rm -rf $root_dir_2/* > /dev/null
	/bin/rm -rf $root_dir_3/* > /dev/null
	/bin/rm -rf $partition_file_1 > /dev/null
	/bin/rm -rf $partition_file_2 > /dev/null
	/bin/rm -rf $partition_file_3 > /dev/null
	/bin/rm -rf "$img_file.xz" "$img_file" > /dev/null
	
	ensure cp -r ../ohx_fs/* $root_dir_3/
}

download() {
	if [ ! -d xbps ]; then
		say "Downloading xbps"
		ensure wget -q ${repository}/static/xbps-static-latest.x86_64-musl.tar.xz -O file.tar.xz
		ensure mkdir xbps
		say "Extracting xbps"
		ensure tar xJf file.tar.xz -C xbps
		rm file.tar.xz
	fi

	if [ ! -f "$rootfs_file" ]; then
		say "Downloading void $voidversion for $MACHINE on $ARCH"
		ensure wget -q "$rootfsbase" -O "$rootfs_file"
	fi

	upx_url=https://github.com/upx/upx/releases/download/v3.95/upx-3.95-amd64_linux.tar.xz
	if [ ! -f "upx" ]; then
		say "Downloading upx"
		ensure wget -q ${upx_url} -O upx.tar.xz
		ensure mkdir -p tmp
		ensure tar xJf upx.tar.xz --strip-components=1 -C tmp
		ensure rm upx.tar.xz
		ensure mv tmp/upx upx
		ensure rm -rf tmp
	fi

	if [ ! -f "$ARCH-$dockerfile" ] && [ ! -z $pkg_docker_engine ]; then
		say "Downloading $pkg_docker_engine"
		ensure wget "$pkg_docker_engine" -O "$ARCH-$dockerfile"
	fi
}

prepare_rootfs() {
	if [ -d "${root_dir_2}_cache_$ARCH_$MACHINE" ]; then
		say "Using cached rootfs"
		ensure  cp -r ${root_dir_2}_cache_$ARCH_$MACHINE/* "$root_dir_2/"
	else
		say "Extracting rootfs"
		export XZ_DEFAULTS="-T 0"
		# We need a usernamespace here. Extracted .tar files should stay respective user-id owned.
		ensure_namespaced tar xf "$rootfs_file" --numeric-owner --preserve-permissions -C "$root_dir_2"
		mkdir -p "${root_dir_2}_cache_$ARCH_$MACHINE"
		ensure cp -r ${root_dir_2}/* "${root_dir_2}_cache_$ARCH_$MACHINE/"
	fi
	
	# We assume sd-cards for all SOCs, formated with an MBR
	if [ "$machine" != "uefi" ]; then
		ensure  echo '/dev/mmcblk0p1 /boot vfat defaults 0 0' >> "$root_dir_2/etc/fstab"
		ensure  echo '/dev/mmcblk0p3 /var ext4 defaults 0 0' >> "$root_dir_2/etc/fstab"
	else
		# We assume a GPT disk layout for uefi systems
		ensure  echo "UUID=$gpt_uuid_boot /boot vfat defaults 0 0" >> "$root_dir_2/etc/fstab"
		ensure  echo "UUID=$gpt_uuid_data /var ext4 defaults 0 0" >> "$root_dir_2/etc/fstab"
	fi
	ensure  echo 'overlay /etc overlay lowerdir=/etc,upperdir=/var/etc_rw,workdir=/var/etc_rw_work 0 0' >> "$root_dir_2/etc/fstab"

	# Disable swap
	ensure rm $root_dir_2/etc/runit/core-services/04-swap.sh
	# Apply some boot changes:
	# - We want a read only squashfs filesystem.
	# - We want to resize the last partition.
	# - We want an overlayfs for /etc
	# - Create necessary users/groups
	ensure cp ../res/runit/* $root_dir_2/etc/runit/core-services/
	ensure cp ../res/growpart.sh $root_dir_2/usr/bin
	ensure chmod +x $root_dir_2/usr/bin/growpart.sh
	
	say "Move /var into own partition"
	ensure mv $root_dir_2/var/* "$root_dir_3/"

	if [ "$MACHINE" = "uefi" ]; then
		# uefi rootfs do not contain a kernel.
		# This is installed by "xbps-install -S linux" and moved to "$root_dir_1/" in a later step.
		say "Postpone kernel installation for $ARCH"
	else
		# SOC rootfs images have a boot directory
		ensure mv $root_dir_2/boot/* "$root_dir_1/"
		# Mount root readonly
		[ -f $root_dir_1/cmdline.txt ] && sed -i -e 's/ rw / ro noswap /' $root_dir_1/cmdline.txt
	fi

	# Overlayfs directories
	mkdir -p $root_dir_3/etc_rw
	mkdir -p $root_dir_3/etc_rw_work
	
	# Extract docker engine archive into bin directory
	if [ ! -z $pkg_docker_engine ] && [ ! -d dockerbin_cache ]; then
		rm -rf tmp > /dev/null
		mkdir -p tmp
		say "Strip docker binaries"
		ensure tar xaf $ARCH-$dockerfile --owner=root --group=root --strip-components=1 -C tmp
		if [ "$ARCH" = "x86_64" ]; then
			find tmp/ -type f -exec strip "{}" \;
		else
			local execute="docker run -v ./tmp:/mnt:Z --rm -t muslcc/x86_64:$ARCH-linux-musl"
			ensure $execute find /mnt/ -type f -exec strip "{}" \;
		fi
		say "Compress docker binaries"
		ensure ./upx -q tmp/*
		mkdir -p dockerbin_cache
		mv tmp/* dockerbin_cache/
	fi
	# Create service file for docker executable
	if [ -d dockerbin_cache ]; then
		ensure cp -r dockerbin_cache/* $root_dir_2/bin
		ensure mkdir $root_dir_2/etc/sv/dockerd
		ensure echo "#!/bin/sh" > $root_dir_2/etc/sv/dockerd/run
		ensure echo "exec /usr/bin/dockerd -l error" >> $root_dir_2/etc/sv/dockerd/run
		ensure chmod +x $root_dir_2/etc/sv/dockerd/run	
	fi
	
	# Network: Nameserver + hostname
	ensure echo "nameserver 8.8.8.8" > $root_dir_2/etc/resolv.conf
	ensure echo "nameserver 8.8.4.4" >> $root_dir_2/etc/resolv.conf
	ensure echo "ohx" >> $root_dir_2/etc/hostname
	
	# Start wpa supplicant with "-u" (dbus interface)
	mkdir -p $root_dir_2/etc/sv/wpa_supplicant
	ensure echo "#!/bin/sh" > $root_dir_2/etc/sv/wpa_supplicant/run
	ensure echo "exec wpa_supplicant -M -c /etc/wpa_supplicant/wpa_supplicant.conf -s -u" >> $root_dir_2/etc/sv/wpa_supplicant/run
	
	# Add network services and provisioning scripts to start up process
	local services=( chronyd dockerd dbus NetworkManager avahi-daemon sshd ) #dhcpcd
	for service in ${services[@]}; do
		ensure ln -sf /etc/sv/${service} $root_dir_2/etc/runit/runsvdir/default/
	done
	ensure  ln -sf /mnt/data/provisioning/scripts $root_dir_2/etc/runit/runsvdir/default
	
	# Replace root password. Add some system users
	local HASH="root:$(mkpasswd --method=SHA-512 $rootpwd -s ce5Cm/69pJ3/fe):18209:0:99999:7:::"
	ensure sed -i "1s@.*@$HASH@" "$root_dir_2/etc/shadow"
}

function join_by { local IFS="$1"; shift; echo "$*"; }

install_pkgs() {
	local pkg_str=$(join_by " " "${pkgs[@]}")
	#local pkgs=musl
	local pkgs_dir=./pkgs_cache/$ARCH
	mkdir -p $pkgs_dir

	export SSL_NO_VERIFY_HOSTNAME=1
    export SSL_NO_VERIFY_PEER=1
	
	export XBPS_ARCH=$ARCH-musl
	export XBPS_TARGET_ARCH=$ARCH-musl
	say "Update package repository index"
    ensure echo "Y" | xbps/usr/bin/xbps-install.static \
    --repository=${repository}/current/$repo_suffix -r $pkgs_dir -yS > /dev/null 2>&1

	say "Download and install packages: $pkg_str"
	ensure echo "Y" | xbps/usr/bin/xbps-install.static \
	--repository=${repository}/current/$repo_suffix -r $pkgs_dir -y $pkg_str > /dev/null
	
	if [ "$MACHINE" = "uefi" ]; then
		say "Install kernel"
		ensure echo "Y" | xbps/usr/bin/xbps-install.static \
		--repository=${repository}/current/$repo_suffix -r $pkgs_dir -y linux grub > /dev/null
		say "Copy kernel into boot partition"
		ensure cp -r $pkgs_dir/boot/* $root_dir_1/
		local bootdir=$root_dir_1
		local modules=( fat exfat part_gpt normal boot linux configfile loopback chain ls search search_label search_fs_uuid search_fs_file test all_video loadenv efifwsetup )
		mkdir -p $bootdir/EFI/Boot
		ensure grub2-mkimage -o $bootdir/EFI/Boot/bootx64.efi --prefix=/boot/grub -O $GRUB_ARCH-efi $modules
		ensure cp ../res/grub.cfg $bootdir/EFI/Boot/grub.cfg
	fi

	# Remove package cache data and db (~40MB)
	say "Copy package data into /var"
	# Move new /var files to 3rd partition (our /var partion)
	ensure cp -r $pkgs_dir/var/* $root_dir_3/
	ensure rm -rf $root_dir_3/cache/xbps* $root_dir_3/db/xbps*/https*
	pkg_size=$(($(du -b "$pkgs_dir"|tail -n1|cut -f1) / $mega))
	say "Copy package data into rootfs ($pkg_size MB)"
	pushd $pkgs_dir > /dev/null
	ensure_namespaced cp -r $(ls -A | grep -v "var" | grep -v "boot") $root_dir_2/
	popd > /dev/null
	ensure rm -rf $root_dir_2/var/*
	ensure rm -rf $root_dir_2/boot/*
	# Test
	if [ ! -f $root_dir_2/usr/bin/avahi-daemon ]; then
		err "Package check failed. No $root_dir_2/usr/bin/avahi-daemon"
	fi
}

install_software_containers() {
	say "Provision containers"
	local container_str=$(join_by " " "${containers[@]}")
	local TARGET=./container_cache/$ARCH
	ensure mkdir -p $TARGET
	ensure mkdir -p ./$root_dir_3/lib/docker
	touch $TARGET/ok
	ensure docker run -v $TARGET:/var/lib/docker:Z --privileged -e ARCH=$ARCH -it docker_run $container_str 
	cp -r $TARGET/* ./$root_dir_3/lib/docker
}

# Removing junk (trims down by about 60 MB)
cleanup_image() {
	say "Cleanup partitions"
	ensure rm -rf $root_dir_2/usr/share/man/* $root_dir_2/usr/share/info/* \
		$root_dir_2/usr/share/void-artwork $root_dir_2/usr/share/misc/* \
		$root_dir_2/media $root_dir_2/opt
	# Javascript engine (mozjs60) is used for NetworkManager scripted proxy support. We don't use that.
	ensure echo "" > $root_dir_2/usr/bin/js60
	ensure pushd $root_dir_2/usr/share/locale > /dev/null
	ensure find . -maxdepth 1 -type d ! -name 'en*' -and ! -name 'de*' -and ! -name '.' -exec rm -rf {} +
	ensure popd > /dev/null
	rm -rf $root_dir_3/empty $root_dir_3/opt $root_dir_3/spool $root_dir_3/mail
}

create_img() {
	local partition_size_1=$(($(du -b "$root_dir_1"|tail -n1|cut -f1) + 15 * $mega))
	local partition_size_2=$(($(du -b "$root_dir_2"|tail -n1|cut -f1) + 50 * $mega))
	local partition_size_3=$(($(du -b "$root_dir_3"|tail -n1|cut -f1) + 5 * $mega))
	local partition_size_1_m=$(($partition_size_1 / $mega))
	local partition_size_2_m=$(($partition_size_2 / $mega))
	local partition_size_3_m=$(($partition_size_3 / $mega))
	
	# Create the 3 raw images.
	say "Creating boot partition ($partition_size_1_m MB)"
	
	rm -f "$partition_file_1"
	ensure dd if=/dev/zero "of=$partition_file_1" count=$(($partition_size_1/$bs)) bs="$bs" status=none
	ensure_quiet mkfs.vfat -n "Boot" "$partition_file_1"
	ensure pushd "$root_dir_1" > /dev/null
	# -b batch mode; -Q quits on first error; -s recursive
	ensure mcopy -bQs -i "$partition_file_1" * "::"
    ensure popd > /dev/null
	partition_size_1=$(wc -c "$partition_file_1"|cut -d' ' -f1)

	say "Creating data partition ($partition_size_3_m MB)"
	rm -f "$partition_file_3"
	ensure mke2fs -q -d "$root_dir_3" -L "Data" "$partition_file_3" "${partition_size_3_m}m"
	partition_size_3=$(wc -c "$partition_file_3"|cut -d' ' -f1)
	
	say "Creating rootfs partition ($partition_size_2_m MB)"

	# Reserved blocks: 0 (-m), reserved i nodes:0  (-N) ,^large_file,^resize_inode,sparse_super,uninit_bg
	rm -f "$partition_file_2"
	ensure_namespaced mke2fs -q -d "$root_dir_2" -O "^has_journal,^large_file,^resize_inode,sparse_super,uninit_bg" \
	  -N 0 -m 0 -L "Root" "$partition_file_2" "${partition_size_2_m}m"
	partition_size_2=$(wc -c "$partition_file_2"|cut -d' ' -f1)
	
	if [ "$MACHINE" = "uefi" ]; then
		# Partition start blocks are aligned to a 2048 block boundary.
		# Computing the total size happens therefore iteratively here.
		block_round=$((2048 * $block_size))
		partition_start1=$((2048 * $block_size))
		partition_start2=$(($partition_start1 + $(echo $partition_size_1 | jq -R "tonumber/$block_round|ceil*$block_round")))
		partition_start3=$(($partition_start2 + $(echo $partition_size_2 | jq -R "tonumber/$block_round|ceil*$block_round")))
		partition_start4=$(($partition_start3 + $(echo $partition_size_3 | jq -R "tonumber/$block_round|ceil*$block_round")))
		local COUNT=$(($partition_start4 + $partition_start1)) # Add size of GTP header at the end
		
		say "Create GUID Partition Table ($(($COUNT/$block_size)) Blocks)"
		ensure dd if=/dev/zero of="$img_file" bs=$bs count=$(($COUNT/$bs)) conv=fsync status=none
		
		local guid_root=$guid_root_x86_64
		[ "$ARCH" == "aarch64" ] && guid_root=$guid_root_aarch64
		# uuids are random/generated
		printf "label: gpt
		label-id: D8DC3F51-DCAA-4C8C-B3D7-EA6ADC829CF9
		table-length: 3
		type=$guid_efi_system, size=$(($partition_size_1/$block_size)), bootable, uuid=$gpt_uuid_boot, name=Boot
		type=$guid_root, size=$(($partition_size_2/$block_size)), uuid=5B8B1CF4-A735-4256-892E-E3089283E71F, name=Root
		type=$guid_linux_data, size=$(($partition_size_3/$block_size)), uuid=$gpt_uuid_data, name=Data
		" | sfdisk -q "$img_file"
	else
		local COUNT=$(($partition_size_3 + $partition_size_2 + $partition_size_1 + 2**20))
		
		say "Create msdos partition layout ($(($COUNT/$block_size)) Blocks)"
		ensure dd if=/dev/zero of="$img_file" bs="$bs" count=$(($COUNT/$bs)) status=none
		printf "label: dos
		type=b, size=$(($partition_size_1/$block_size)), bootable
		type=83, size=$(($partition_size_2/$block_size))
		type=83, size=$(($partition_size_3/$block_size))
		" | sfdisk -q "$img_file"
	fi
	
	rm -rf tmp > /dev/null
	mkdir -p tmp
	
	# partfs allows us to user mount the image file so that we can use dd on block devices instead of manually
	# computing the offset. The later variant highly depends on the used sfdisk version and partition alignment.
	# -f: foreground, so that we can get the pid in the next line. -o: The image file
	./partfs tmp -f -o dev="$img_file",direct_io,auto_unmount &
	local partfs_pid=$!
	if ! ps -p $partfs_pid > /dev/null; then
		err "Failed to start 'partfs'"
	fi
	say "Started partfs with pid $partfs_pid"

	say "Add boot partition to img file"
	ensure dd if="$partition_file_1" of="tmp/p1" bs=$bs conv=fsync status=none
	say "Add root partition to img file"
	ensure dd if="$partition_file_2" of="tmp/p2" bs=$bs conv=fsync status=none
	say "Add data partition to img file"
	ensure dd if="$partition_file_3" of="tmp/p3" bs=$bs conv=fsync status=none

	ensure kill $partfs_pid
	wait $partfs_pid
	rm -rf tmp/
	
	rm "$partition_file_1"
	rm "$partition_file_2"
	rm "$partition_file_3"
	
	IMAGESIZE=$(ls -lh $img_file|awk '{print $5}')
	say "Image $img_file size: $IMAGESIZE"

	if [[ -z "${SKIP_COMPRESSION}" ]]; then
		say "Compressing image to $img_file.xz"
		export XZ_DEFAULTS="-T 0"
		trap "{ rm -f "$img_file.xz.part" ; exit 2; }" TERM EXIT
		tar -cJf "$img_file.xz.part" "$img_file"
		rm -rf "$img_file.xz" > /dev/null
		mv "$img_file.xz.part" "$img_file.xz"
		trap "exit 1" TERM
		IMAGESIZE=$(ls -lh $img_file.xz|awk '{print $5}')
		say "Compressed size: $IMAGESIZE"
	else
		say "Skipping compression to $img_file.xz"
	fi
}

need_cmd() {
    if ! command -v "$1" > /dev/null 2>&1; then
        err "need '$1' (command not found) $2"
    fi
}

ensure() {
    "$@"
    if [ $? != 0 ]; then
        err "ERROR: command failed: $*";
    fi
}

ensure_quiet() {
    "$@" 2>&1 > outfile
    if [ $? != 0 ]; then
		echo "ERROR: command failed: $*"
		cat outfile
		rm outfile
        err "command failed: $*";
    fi
    rm outfile > /dev/null
}

# To preserve file ownerships without being root, this
# function will execute the given command in a user-namespace
# or fakeroot environment
ensure_namespaced() {
	#  echo "$@"
	fakeroot "$@"
    #echo "$@" | unshare --map-root-user
    if [ $? != 0 ]; then
        err "ERROR: command failed: $*";
    fi
}

say() {
	local color=$( tput setaf 2 )
	local normal=$( tput sgr0 )
	echo "${color}$1${normal}"
}

err() {
	local color=$( tput setaf 1 )
	local normal=$( tput sgr0 )
	echo "${color}$1${normal}" >&2
	exit 1
}

start=`date +%s`

prerequirements || exit 1
download || exit 1
prepare_rootfs || exit 1
install_pkgs || exit 1
install_software_containers || exit 1
cleanup_image || exit 1
create_img || exit 1

end=`date +%s`
runtime=$((end-start))
say "Finished in $runtime seconds"
trap "exit 0" EXIT
