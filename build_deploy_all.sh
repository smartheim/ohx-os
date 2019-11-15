#!/bin/sh -e

build_one() {
	MACHINE="$1"
	ARCH="$2"
	BASEIMG="voidlinux/ohx-$MACHINE.img"
	if [ ! -f $BASEIMG ]; then
		ARCH=$ARCH MACHINE=$MACHINE sh build_one_arch.sh
	fi
}

# Attach binary to Github release. Remove existing one if necessary.
deploy() {
	MACHINE="$1"
	ARCH="$2"
	IMAGE_FILE="voidlinux/ohx-$MACHINE.img"
	DEPLOY_FILE="voidlinux/ohx-$MACHINE.img.gz"
	
	# rm $IMAGE_FILE $DEPLOY_FILE
}

# Create Github release if not yet existing
prepare_release() {

}

build_all() {
   prepare_release
   build_one rpi3 aarch64
   deploy rpi3 aarch64
}

build_all "$@" || exit 1
