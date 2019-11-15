#!/bin/sh -e
if [ ! -f /var/lib/docker/ok ]; then
	echo "No ok file!"
	exit 1
fi

# Normalize. Void calls those architectures differently.
[ "$ARCH" == "aarch64" ] && ARCH=arm64
[ "$ARCH" == "x86_64" ] && ARCH=amd64
[ "$ARCH" == "armv7l" ] && ARCH=arm

case $ARCH in
    amd64|arm64|arm) echo "For Architecture: $ARCH";;
    *)             echo "Architecture invalid"; exit 1 ;;
esac

mkdir -p /etc/docker/
mkdir -p ~/.docker

echo '{"experimental":true}' > /etc/docker/daemon.json
echo '{"experimental":"enabled"}' > ~/.docker/config.json
dockerd-entrypoint.sh &
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15
do
	if [ -S /var/run/docker.sock ]; then
		echo "Docker daemon ready. Install containers"
		sleep 1
		for var in "$@"
		do
			set +e
			docker image rm "$var" > /dev/null
			set -e
			docker pull --platform="linux/$ARCH"  "$var"
			echo -n "Inspect $var: "
			docker inspect --format="{{.Architecture}}" "$var"
		done
		kill %1
		exit 0
	fi
sleep 1
done

echo "Failed"
kill %1
exit 1
