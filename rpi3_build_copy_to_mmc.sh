#!/bin/sh -e

: "${TARGET:=/dev/mmcblk0}"
: "${ARCH:=aarch64}"
: "${MACHINE:=rpi3}"

BASEIMG="voidlinux/ohx-$MACHINE.img"

if [ ! -b $TARGET ]; then
   echo "Target not readable: $TARGET"
   exit
fi

if [ ! -f $BASEIMG ]; then
   ARCH=$ARCH MACHINE=$MACHINE SKIP_COMPRESSION=true sh build_one_arch.sh
fi

# Unmount
set +e
sudo umount ${TARGET}* > /dev/null &2>1
set -e

IMAGESIZE=$(ls -lh $BASEIMG|awk '{print $5}')
echo "Copy $IMAGESIZE to mmc"
sudo dd if=$BASEIMG of=$TARGET bs=4M status=progress oflag=direct,sync
