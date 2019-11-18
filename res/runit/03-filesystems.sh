# vim: set ts=4 sw=4 et:

[ -n "$VIRTUALIZATION" ] && return 0

msg "Checking /var"
mount -o ro /var || emergency_shell

[ -f /fastboot ] && FASTBOOT=1
[ -f /forcefsck ] && FORCEFSCK="-f"
for arg in $(cat /proc/cmdline); do
    case $arg in
        fastboot) FASTBOOT=1;;
        forcefsck) FORCEFSCK="-f";;
    esac
done

# A file may indicate that we should not attempt a resize
for f in /var/noresize; do
	NO_RESIZE="1"
done

umount /var

resize_part() {
	DEVICE=/dev/mmcblk0
	PARTNR=3
	TARGET=${DEVICE}p${PARTNR}
	msg "Resize partion $TARGET"
	mount -t tmpfs -o size=1M tmpfs /tmp || emergency_shell
	RES=$(/usr/bin/growpart.sh $DEVICE $PARTNR |cut -d" " -f1)
	RET_VAL=$?
	umount /tmp
	[ $? -ne 0 ] && emergency_shell

	if [ "${RES}" != "NOCHANGE:" ]; then
		echo "[Resize] Copy data to tmpfs"
		mount -t tmpfs -o size=200M tmpfs /mnt || emergency_shell
		mount -o ro /var || emergency_shell
		cp -r /var/* /mnt || emergency_shell
		umount /var || emergency_shell
		echo "[Resize] Recreate ext4 filesystem"
		mkfs.ext4 -F ${TARGET} || emergency_shell
		mount /var || emergency_shell
		cp -r /mnt/* /var || emergency_shell
		echo "[Resize] Unmount tmpfs"
		umount /mnt || emergency_shell
		echo "[Resize] Done"
	fi
}

# A resized partition is basically a newly created filesystem, no need to check
if [ ! -z "$NO_RESIZE" ]; then
	resize_part
elif [ -z "$FASTBOOT" ]; then
    msg "Checking filesystems:"
    fsck -A -T -a -t noopts=_netdev $FORCEFSCK
    if [ $? -gt 1 ]; then
        emergency_shell
    fi
fi

msg "Mounting all non-network filesystems..."
mount -a -t "nosysfs,nonfs,nonfs4,nosmbfs,nocifs" -O no_netdev || emergency_shell
