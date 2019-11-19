#!/bin/sh -e

: "${ROOTDEV:=/dev/mmcblk0p2}"
: "${ARCH:=aarch64}"
: "${MACHINE:=rpi3}"
: "${KERNEL:=kernel8.img}"
: "${DTB:=bcm2710-rpi-3-b.dtb}"

QEMU_MACHINE=$MACHINE
[ "$MACHINE" = "rpi3" ] && QEMU_MACHINE=raspi3
[ "$MACHINE" = "rpi2" ] && QEMU_MACHINE=raspi2

#kernel_cmd_line=$(cat voidlinux/boot/cmdline.txt)
kernel_cmd_line="rw console=ttyAMA0,115200 net.ifnames=0 rootwait loglevel=4 root=${ROOTDEV} rootfstype=ext4"
BASEIMG="voidlinux/ohx-$MACHINE-$ARCH.img"

if [ ! -f "$BASEIMG" ] || [ ! -f "voidlinux/boot/$KERNEL" ]  || [ ! -f "voidlinux/boot/$DTB" ]; then
   SKIP_COMPRESSION=true sh build_one_arch.sh $MACHINE $ARCH
fi

#echo "hdmi_mode=16" >> "voidlinux/boot/config.txt"

#	-net nic -net user,hostfwd=tcp::5022-:22 \
qemu-system-aarch64 \
	-serial stdio \
	-kernel voidlinux/boot/$KERNEL -dtb voidlinux/boot/$DTB \
	-m 1024 -M $QEMU_MACHINE -drive file=$BASEIMG,format=raw,if=sd \
	-append "$kernel_cmd_line"
