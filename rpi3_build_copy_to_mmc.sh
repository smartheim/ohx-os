#!/bin/sh -e

: "${TARGET:=/dev/mmcblk0}"
: "${ARCH:=aarch64}"
: "${MACHINE:=rpi3}"

BASEIMG="voidlinux/ohx-$MACHINE.img"

if [ ! -f $TARGET ]; then
   echo "Target not found: $TARGET"
   exit
fi

if [ ! -f $BASEIMG ]; then
   ARCH=$ARCH MACHINE=$MACHINE SKIP_COMPRESSION=true sh build_one_arch.sh
fi

IMAGESIZE=$(ls -lh $BASEIMG|awk '{print $5}')
echo "Copy $IMAGESIZE to mmc"
sudo dd if=$BASEIMG of=$TARGET bs=1M status=progress
