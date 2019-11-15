#!/bin/bash

if [ -f $MACHINE ]; then
   echo "You must set MACHINE, for exmple to 'rpi3'"
   exit
fi

if [ -f $ARCH ]; then
   echo "You must set ARCH, for exmple to 'aarch64'"
   exit
fi

trap "exit 1" TERM

# Input params.
readonly rootpwd=ohxsmarthome
readonly target="$MACHINE"
readonly rootfs_file="void-$target-musl-PLATFORMFS"

# Normalize. Void calls those architectures differently.
DOCKER_ARCH=$ARCH
[ "$ARCH" == "armv7l" ] && DOCKER_ARCH=armhf

# Constants

readonly rootfsbase="https://alpha.de.repo.voidlinux.org/live/20191109/$rootfs_file-20191109.tar.xz"
readonly repository="https://alpha.de.repo.voidlinux.org"
readonly rootfs_file="void-$target-root.tar.xz"
readonly img_file="ohx-$target.img"
readonly dockerfile="docker-19.03.4.tgz"

readonly mega="$(echo '2^20' | bc)"

readonly root_dir_1=boot
readonly partition_file_1=part1.fat
readonly partition_size_1_megs=64
readonly partition_size_1=$(($partition_size_1_megs * $mega))

readonly root_dir_2=rootfilesystem
readonly partition_file_2=part2.ext4
readonly partition_size_2_megs=550
readonly partition_size_2=$(($partition_size_2_megs * $mega))

readonly root_dir_3=ohxfs
readonly partition_file_3=part3.ext4
readonly partition_size_3_megs=20
readonly partition_size_3=$(($partition_size_3_megs * $mega))

readonly bs=1024
readonly block_size=512


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
    need_cmd mcopy "GNU mtools"
    need_cmd mke2fs "e2fsprogs"
    
    local has_images=$(docker images|grep docker_run|wc -l)
    [ $has_images != "1" ] && ensure ./container_helpers/build_containers.sh
    
    # Work directory is "voidlinux"
	[ ! -d voidlinux ] && ensure mkdir voidlinux
	cd voidlinux

	[ ! -d $root_dir_1 ] && ensure mkdir "$root_dir_1"
	[ ! -d $root_dir_2 ] && ensure mkdir "$root_dir_2"
	[ ! -d $root_dir_3 ] && ensure mkdir "$root_dir_3"
	/bin/rm -rf $root_dir_1/*
	/bin/rm -rf $root_dir_2/*
	/bin/rm -rf $root_dir_3/*
	
	ensure cp -r ../ohx_fs/* $root_dir_3/
}

download() {
	if [ ! -d xbps ]; then
		echo "Downloading xbps"
		ensure wget ${repository}/static/xbps-static-latest.x86_64-musl.tar.xz -O file.tar.xz
		ensure mkdir xbps
		ensure tar xJf file.tar.xz -C xbps
		rm file.tar.xz
	fi

	if [ ! -f "$rootfs_file" ]; then
		echo "Downloading $rootfsbase"
		ensure wget "$rootfsbase" -O "$rootfs_file"
	fi

	case "$ARCH" in
		"armv7l")
			pkg_docker_engine="https://download.docker.com/linux/static/stable/armhf/$dockerfile"
			containers=( "portainer/portainer:linux-arm" )
			pkgs=( "avahi" "NetworkManager" )
			;;
			
		"aarch64")
			pkg_docker_engine="https://download.docker.com/linux/static/stable/aarch64/$dockerfile"
			containers=( "portainer/portainer:linux-arm64" )
			pkgs=( "avahi" "NetworkManager" )
			;;
			
		"x86_64")
			containers=( "portainer/portainer:latest" )
			pkgs=( "avahi" "NetworkManager" "docker" )
			;;
		*)
			err "Unknown architecture $ARCH"
	esac

	if [ ! -f "$ARCH-$dockerfile" ] && [ ! -z $pkg_docker_engine ]; then
		echo "Downloading $pkg_docker_engine"
		ensure wget "$pkg_docker_engine" -O "$ARCH-$dockerfile"
	fi
}

prepare_rootfs() {
	# We need a usernamespace here. Extracted .tar files should stay root owned.

	echo "Extracting rootfs"
	ensure_namespaced tar xf "$rootfs_file" --no-same-owner -C "$root_dir_2"
	mkdir $root_dir_2/mnt/data
	echo '/dev/mmcblk0p1 /boot vfat defaults 0 0' >> "$root_dir_2/etc/fstab"
	echo '/dev/mmcblk0p3 /mnt/data ext4 defaults 0 0' >> "$root_dir_2/etc/fstab"

	# Removing junk (trims down by about 50 MB)
	rm -rf $root_dir_2/usr/share/man/* $root_dir_2/usr/share/info/* $root_dir_2/usr/share/void-artwork $root_dir_2/usr/share/misc/*
	rm -rf $root_dir_2/media $root_dir_2/opt 
	rm -rf $root_dir_2/var/empty $root_dir_2/var/opt $root_dir_2/var/spool $root_dir_2/var/mail
	ensure pushd $root_dir_2/usr/share/locale > /dev/null
	find . -maxdepth 1 -type d ! -name 'en*' -and ! -name 'de*' -and ! -name '.' -exec rm -rf {} +
	ensure popd > /dev/null
	
	# No swap enabled
	ensure rm $root_dir_2/etc/runit/core-services/04-swap.sh
	# Replace runit mounting script. We want a read only filesystem.
	#TODO ensure cp $root_dir_3/provisioning/03-filesystems.sh $root_dir_2/etc/runit/core-services/
	
	ensure mv $root_dir_2/boot/* "$root_dir_1/"
	#TODO ensure mv "$root_dir_2/var" "$root_dir_3/var"
	#TODO ensure ln -s /mnt/data/var "$root_dir_2/var"
	
	# Extract docker engine archive into bin directory
	if [ ! -z $pkg_docker_engine ]; then
		ensure tar xaf $ARCH-$dockerfile --strip-components=1 -C $root_dir_2/bin
		ensure mkdir $root_dir_2/etc/sv/dockerd
		echo "/usr/bin/dockerd" > $root_dir_2/etc/sv/dockerd/run
	fi
	
	# Add network services and provisioning scripts to start up
	local services=( chronyd dockerd dbus networkmanager avahi-daemon sshd ) #dhcpcd
	for service in ${services[@]}; do
		ensure ln -sf /etc/sv/${service} $root_dir_2/etc/runit/runsvdir/default/
	done
	ensure ln -sf /mnt/data/provisioning/scripts $root_dir_2/etc/runit/runsvdir/default
	
	# Replace root password
	local HASH="root:$(mkpasswd --method=SHA-512 $rootpwd -s ce5Cm/69pJ3/fe):18209:0:99999:7:::"
	ensure sed -i "1s@.*@$HASH@" "$root_dir_2/etc/shadow"
}

function join_by { local IFS="$1"; shift; echo "$*"; }

install_pkgs() {
	local pkgs=$(join_by " " "${pkgs[@]}")
	mkdir -p pkgs_temp
	
	export SSL_NO_VERIFY_HOSTNAME=1
    export SSL_NO_VERIFY_PEER=1
	
	export XBPS_ARCH=x86_64-musl
	export XBPS_TARGET_ARCH=x86_64-musl
    ensure echo "Y" | xbps/usr/bin/xbps-install.static \
    --repository=${repository}/current/musl -r ./pkgs_temp/x86_64 -yS

	export XBPS_ARCH=aarch64-musl
	export XBPS_TARGET_ARCH=aarch64-musl
    ensure echo "Y" | xbps/usr/bin/xbps-install.static \
    --repository=${repository}/current/aarch64 -r ./pkgs_temp/aarch64 -yS

	export XBPS_ARCH=armv7l-musl
	export XBPS_TARGET_ARCH=armv7l-musl
	ensure echo "Y" | xbps/usr/bin/xbps-install.static \
    --repository=${repository}/current/musl -r ./pkgs_temp/armv7l -yS

    local suffix=musl
    [ "${ARCH}" == "aarch64" ] && suffix=aarch64
	export XBPS_ARCH=${ARCH}-musl
	export XBPS_TARGET_ARCH=${ARCH}-musl
	
	ensure echo "Y" | xbps/usr/bin/xbps-install.static \
	--repository=${repository}/current/$suffix -r ./pkgs_temp/${ARCH} -yf $pkgs
	
	cp -r pkgs_temp/$ARCH/* $root_dir_2/
}

install_software_containers() {
	local container_str=$(join_by " " "${containers[@]}")
	local TARGET=./$root_dir_2/var/lib/docker
	ensure mkdir -p $TARGET
	touch $TARGET/ok
	ensure docker run -v $TARGET:/var/lib/docker:Z --privileged -e ARCH=$ARCH -it docker_run $container_str 
}

create_img() {
	# Create the 3 raw images.
	echo "Creating boot partition"

	rm -f "$partition_file_1"
	ensure dd if=/dev/zero "of=$partition_file_1" count=$(($partition_size_1/$bs)) bs="$bs"
	ensure mkfs.fat "$partition_file_1" > /dev/null
	# -b batch mode; -Q quits on first error; -s recursive
	ensure pushd "$root_dir_1" > /dev/null
	ensure mcopy -bQs -i "../$partition_file_1" * "::"
    ensure popd > /dev/null

	echo "Creating rootfs partition"
	rm -f "$partition_file_2"
	ensure_namespaced mke2fs \
	  -d "$root_dir_2" \
	  -O \'^64bit,^has_journal\' \
	  -r 1 \
	  -N 0 \
	  -m 5 \
	  -L \'\' \
	  "$partition_file_2" \
	  "${partition_size_2_megs}M"
	
	echo "Creating data partition"
	rm -f "$partition_file_3"
	ensure mke2fs \
	  -d "$root_dir_3" \
	  "$partition_file_3" \
	  "${partition_size_3_megs}M" > /dev/null

	part_table_offset=$((2**20))
	cur_offset=0

	echo "Concat into img file"
	((COUNT = $part_table_offset + $partition_size_1 + $partition_size_2 + $partition_size_3))
	ensure dd if=/dev/zero of="$img_file" bs="$bs" count=$(($COUNT/$bs)) skip="$(($cur_offset/$bs))"
	printf "
	type=b, size=$(($partition_size_1/$block_size)), bootable
	type=83, size=$(($partition_size_2/$block_size))
	type=83, size=$(($partition_size_3/$block_size))
	" | sfdisk "$img_file"

	cur_offset=$(($cur_offset + $part_table_offset))
	ensure dd if="$partition_file_1" of="$img_file" bs="$bs" seek="$(($cur_offset/$bs))"

	cur_offset=$(($cur_offset + $partition_size_1))
	ensure dd if="$partition_file_2" of="$img_file" bs="$bs" seek="$(($cur_offset/$bs))"

	cur_offset=$(($cur_offset + $partition_size_2))
	ensure dd if="$partition_file_3" of="$img_file" bs="$bs" seek="$(($cur_offset/$bs))"

	rm "$partition_file_1"
	rm "$partition_file_2"
	rm "$partition_file_3"
	
	IMAGESIZE=$(ls -lh $img_file|awk '{print $5}')
	echo "Image $img_file size: $IMAGESIZE"

	if [[ -z "${SKIP_COMPRESSION}" ]]; then
		echo "Compressing image to $img_file.xz"
		export XZ_DEFAULTS="-T 0"
		tar -caf "$img_file.xz" "$img_file"
		IMAGESIZE=$(ls -lh $img_file.xz|awk '{print $5}')
		echo "Compressed size: $IMAGESIZE"
	else
		echo "Skipping compression to $img_file.xz"
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
        err "command failed: $*";
    fi
}

ensure_namespaced() {
	#  echo "$@"
    echo "$@" | unshare --map-root-user
    if [ $? != 0 ]; then
        err "command failed: $*";
    fi
}

say() {
    printf '\33[1m%s:\33[0m %s\n' "$APPNAME" "$1"
}

err() {
    printf '\33[1;31m%s:\33[0m %s\n' "$APPNAME" "$1" >&2
    #kill -s TERM $TOP_PID
	exit 1
}

start=`date +%s`
prerequirements || exit 1
download || exit 1
prepare_rootfs || exit 1
install_pkgs || exit 1
install_software_containers || exit 1
create_img || exit 1
end=`date +%s`
runtime=$((end-start))
echo "Finished in $runtime seconds"

