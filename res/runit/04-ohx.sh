#!/bin/bash

mount -o rw,remount / || emergency_shell
[ "$(grep "dbus" < /etc/passwd|wc -l)" = "0" ] && useradd dbus
[ "$(grep "avahi" < /etc/passwd|wc -l)" = "0" ] && useradd avahi
[ "$(grep "polkitd" < /etc/passwd|wc -l)" = "0" ] && useradd polkitd
[ "$(grep "chrony" < /etc/passwd|wc -l)" = "0" ] && useradd chrony
mount -o ro,remount / || emergency_shell

wifi=$(ip link | grep DORMANT | cut -d ":" -f2 | tr -d '[:space:]')
msg "Add IP 192.168.4.1/24 to wifi $wifi link"
[ ! -z "$wifi" ] && ip addr add 192.168.4.1/24 dev $wifi broadcast 255.255.255.0
