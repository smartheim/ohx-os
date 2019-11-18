#!/bin/sh -ex
#kernel_cmd_line=$(cat voidlinux/boot/cmdline.txt)
kernel_cmd_line="rw earlycon=pl011,0x3f201000 console=ttyAMA0 loglevel=8 root=/dev/mmcblk0p2 fsck.repair=yes net.ifnames=0 rootwait memtest=1 -panic=1"

qemu-system-aarch64 \
	-kernel voidlinux/boot/kernel8.img -dtb voidlinux/boot/bcm2710-rpi-3-b.dtb \
	-m 1024 -M raspi3  -serial stdio -drive file=voidlinux/ohx-rpi3.img,format=raw,if=sd \
	-net nic -net user,hostfwd=tcp::5022-:22 \
	-append '$kernel_cmd_line' -no-reboot
