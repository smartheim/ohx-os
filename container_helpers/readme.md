This directory contains helper containers to execute void linux commands
for different architectures.

## Void install Package / How to use
* Have a directory with void rootfs
* Use ARCH to define the architecture
* `docker run  -v ./rootfs:/work:Z -e ARCH=aarch64 -it void_install_pkgs PACKAGE_TO_INSTALL`

## Provision docker containers
* Have a "target" directory. The content will be copied to /var/lib/docker on the rootfs later on.
* Use ARCH to define the architecture
* `docker run -v ./target:/var/lib/docker --privileged -e ARCH=arm64 -it docker_run portainer/portainer:linux-arm64 alpine:latest`
* Some images use the image tag to identify the architecture
