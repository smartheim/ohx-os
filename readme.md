# Container focused operating system for OHX

[![Build Status](https://github.com/openhab-nodes/ohx-os/workflows/test/badge.svg)](https://github.com/openhab-nodes/ohx-os/actions)
[![](https://img.shields.io/badge/license-MIT-blue.svg)](http://opensource.org/licenses/MIT)

> OHX is a modern smarthome solution, embracing technologies like software containers for language agnostic extensibility. Written in Rust with an extensive test suite, OHX is fast, efficient, secure and fun to work on.

This repository hosts scripts to assemble and deploy operating system images with OHX preinstalled.
The images are deployed to the Github releases page of this repo.

Supported systems are:
* Any UEFI equiped x86-64 system like the Intel NUC
* Any UEFI equiped aarch64 system
* The Raspberry PI 2, 3 and 4
* The ODroid C2
* The Cubieboard and Beagleboard

For System-On-A-Chip (SoC) hardware an SD-Card or µSD-Card with >= 1 GB capacity is required.
UEFI systems need a storage medium with at least 2 GB.

## Installation

![What you need](doc/what_you_need.png)

1. Find and download the newest `img` file for your hardware on the [releases page](https://github.com/openhab-nodes/ohx-os/releases).
2. Flash the extracted `img` file to your SD-Card (Raspberry PI etc) or USB-Stick (Intel/AMD PC),
   for example with [MediaWriter](https://github.com/FedoraQt/MediaWriter/releases) or [Etcher](https://www.balena.io/etcher/).

TIP: You can also use this one-line command (RPI3 for an SD-Card as an example):
```
sudo -- sh -c 'wget -q -O - https://github.com/openhab-nodes/ohx-os/releases/latest/ohx-rpi3.img.gz | xz --decompress --stdout | dd bs=2M of=/dev/mmcblk0 if=- oflag=direct,sync'
```

## Usage

Plug your hardware in. The operating system and network services should be up within 30 seconds.
The first start takes a bit longer, because the filesystem is extended to the full SD-Card or USB-Drive size.
For an 16GB SD-Card Class 10 this is about 15 seconds.

**Connection**:
If you do not have a wired connection to your hardware and a wireless chip is present,
the system will bring up a Wifi Hotspot called "OHX Connect".

Please enter the passphrase *"ohxsmarthome"* and enter your Wifi networks credentials
on the captive portal web-page.

**SSH and local access:**
The log-in user is called "root" with a default password *"ohxsmarthome"*.
The sytem announces itself also as "ohx.local" and "ohx_ID.local" (with ID being a unique ID) on your network.
Your host system must understand Avahi/Bonjour Service Discovery for this local domain name resolution to work.

You rarely want to login to your system though.
You extend your installation via software containers and not via local packages.
Remember that the root partition is read-only.

**Generic software container management**:
You can fetch, install, start and stop any Docker compatible container via [Portainer](https://www.portainer.io/).
Find it the management User Interface (UI) on https://ohx.local:9000 (within your local network).
Login with "admin" and the password *"ohxsmarthome"*.

**OHX Smarthome**:
The Setup and Maintenance UI of OHX is located at https://ohx.local.
Login with the pre-selected administrative user and the password *"ohxsmarthome"*.

**Password**: After your first login to the Setup and Maintenance UI you will be prompted to
change to a new password. This password will be applied to:
- The operating systems root user
- The wifi access point that comes up when no network connection can be detected,
- The portainer web-ui.

## About the operating system

The operating system is based on [Void Linux](https://voidlinux.org/) and comes with only the most basic userland tools.
All exciting apps and services run in software containers.

The system consists of three partitions:
A small FAT based one with the boot code and kernel, a second, read-only ext4-no-journal based one for the root filesystem
and a third ext4 one that is extended to the full SD-CARD or USB-Drive size on start.

Software containers are stored on the third partition.
Each OHX Addon gets an ext4 disk quota limited space for configuration: `/var/ohx/config/ADDON_NAME`.

For now the software container engine is Docker (so that [Portainer](https://www.portainer.io/) can be used).
Generic container installation and management happens via *Portainer* or the `docker` CLI when logged in with SSH.

OHX Addon management can either happen via *Portainer* or via the Setup and Maintenance web interface of OHX.

### Security

The rootfs is read-only and the data partition filesystem is mounted in a way ("noexec"), that it doesn't allow executables to be run.
This is to prevent attackers from manifesting malicous tools onto disk.
Attackers still may run malious code from memory by exploiting one of the running services.

Because the docker daemon runs as root, a potential attack scenario includes breaking out of a container.
Containers running with "--privileged" are an especially exploitable target.

**You should restrict containers to the minimum necessary privileges.**

A mitigation strategy is to keep the kernel and the Docker engine up to date
and warn on starting up privileged containers.

The following services are running:

* Docker engine. No externally open ports, only a unix socket.
* chronyd: Time sync daemon. Will periodically request the time from ntp servers.
* dbus: The dbus system bus. Required for NetworkManager and wifi-captive.
* NetworkManager: Manages network connections and provides a unified interface over wifi connections (wpa_supplicant / iwd).
* wifi-captive: Port 80 on wifi interfaces that are in access point mode (in contrast to station mode).
* OHX: Port 80 and 443 (http/s and gRPC) are open.
  The underlying web and grpc server are written in Rust and have rate limits and accepted payload size limits applied.
* Avahi: Periodic mdns announcements are send and dns-sd queries are answered.

### Other evaluated systems

openSUSE Kubic (which is a variant of openSUSE MicroOS) with customized [Ignition](https://en.opensuse.org/Kubic:MicroOS/Ignition)
and cloud-init first-boot scripts is an option.

BalenaOS is more mature, but does have a strong bound to the balena cloud and an own supervisior. 
It has a very sophisticated (but also complex) snapshot system and failsafe update mechanism based on A/B partitions and btrfs filesystem snapshots. The rootfs is read-only and multiple overlayfs filesystems allow write modifications.

It also use the original docker daemon, instead of a rootless software container alternative like it is done with Redhats Fedora IoT and openSUSEs Kubic.

Fedora IoT as well as openSUSE Kubic both have a boot time of about 5 minutes and only support a very limited selection of single board ARM systems (fedora: RPI3, openSUSE: RPI3, Pine64). A rather large portion of the system memory is occupied with services that are of no use to OHX.

A non-goal for OHX-OS is a custom build OS, based on [buildroot](https://buildroot.org/).
This would require a custom update mechanism, CVE tracker and more and is not the focus of the OHX project.

## Updates

The only crucial parts that benefit from updating are the kernel and the docker engine.
Both require a reboot of the system. Therefore no live update mechanism has been integrated.

Instead, pull out your storage medium (SD-Card, USB Drive) and overwrite the first two partitions
with the first two partitions of a newly downloaded OS image.

All your data, containers and settings will be kept.

## Build and Deployment

Deploy to hardware:

If you just want to build and deploy to an SD Card, use `rpi3_build_copy_to_mmc.sh`.
You might want to change the sd-card device file, the default is */dev/mmcblk0*,
and target machine, default is the Raspberry PI 3.

Maintainer:

*Prerequirements*: A github token file (`github_token.inc`) with a credentials line following the pattern "GITHUB_TOKEN=access_token". Create an access token in the OHX organisation page.

Modify and adapt packages and provisioned containers in `packages.inc`.

Call `build_deploy_all.sh` to build and deploy for all supported architectures.
This will parse the CHANGELOG file and creates a new Github release if necessary
and attaches all generated, compressed image files.

## Future plans

* Reduce image size and complexity by not using NetworkManager but connman instead (~80MB less)
* Switch userspace to busybox (~30MB less)
* Use podman instead of docker. Removes the root-running daemon. Root is only required for privileged containers. And saves about 20MB.
