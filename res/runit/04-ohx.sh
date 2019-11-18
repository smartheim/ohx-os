#!/bin/bash

mount -o rw,remount / || emergency_shell
[ "$(grep "dbus" < /etc/passwd|wc -l)" = "0" ] && useradd dbus
[ "$(grep "avahi" < /etc/passwd|wc -l)" = "0" ] && useradd avahi
[ "$(grep "polkitd" < /etc/passwd|wc -l)" = "0" ] && useradd polkitd
[ "$(grep "chrony" < /etc/passwd|wc -l)" = "0" ] && useradd chrony
mount -o ro,remount / || emergency_shell
