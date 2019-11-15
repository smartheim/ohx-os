#!/bin/sh
export REPOSITORY=https://alpha.de.repo.voidlinux.org
export SSL_NO_VERIFY_HOSTNAME=1
export SSL_NO_VERIFY_PEER=1
export XBPS_ARCH=${ARCH}-musl
export XBPS_TARGET_ARCH=${ARCH}-musl

cp -r /target/${ARCH} /work
if [ "${ARCH}" == "x86_64" ]; then
	/${ARCH}/usr/bin/xbps-install.static --repository=${REPOSITORY}/current -r /work/${ARCH} -yf $@;
elif [ "${ARCH}" == "aarch64" ]; then
	qemu-${ARCH}-static /${ARCH}/usr/bin/xbps-install.static --repository=${REPOSITORY}/current/aarch64 -r /work/${ARCH} -yf $@
else
	qemu-${ARCH}-static /${ARCH}/usr/bin/xbps-install.static --repository=${REPOSITORY}/current -r /work/${ARCH} -yf $@
fi
