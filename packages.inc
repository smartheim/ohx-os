#!/bin/bash

# License: MIT
# David Graeff <david.graeff@web.de> - 2019

# Define packages to be installed. Have a look at https://voidlinux.org/packages/ for a selection.
# Docker images are defined here as well. For each defined image a 
# The docker engine should be kept up to date as well.

readonly dockerfile="docker-19.03.4.tgz"

case "$ARCH" in
	"armv7l")
		readonly pkg_docker_engine="https://download.docker.com/linux/static/stable/armhf/$dockerfile"
		readonly containers=( "portainer/portainer:linux-arm" )
		readonly pkgs=( "avahi" "NetworkManager" )
		readonly repo_suffix="musl"
		;;
		
	"aarch64")
		readonly pkg_docker_engine="https://download.docker.com/linux/static/stable/aarch64/$dockerfile"
		readonly containers=( "portainer/portainer:linux-arm64" )
		readonly pkgs=( "avahi" "NetworkManager" )
		readonly repo_suffix="aarch64"
		;;
		
	"x86_64")
		readonly pkg_docker_engine="https://download.docker.com/linux/static/stable/x86_64/$dockerfile"
		readonly containers=( "portainer/portainer:latest" )
		readonly pkgs=( "avahi" "NetworkManager" )
		readonly repo_suffix="musl"
		;;
	*)
		err "Unknown architecture $ARCH"
esac

