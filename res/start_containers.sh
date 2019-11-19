#!/bin/bash

readonly START_DIR="/var/container_firststart"
#START_DIR="/home/david/Programming/ohx/ohx-os/ohx_fs/container_firststart"

msg() {
    printf "\033[1m=> $@\033[m\n"
}

msg_ok() {
    printf "\033[1m\033[32m OK\033[m\n"
}

msg_error() {
    printf "\033[1m\033[31mERROR: $@\033[m\n"
}

start_container() {
	local running_images=$(docker container list)
	for f in $START_DIR/*.sh; do
		unset PRE_COMMAND
		unset IMAGE_LABEL
		unset IMAGE_NAME
		unset COMMAND_LINE
		source $f
		local labels=""

		IFS=' '
		for label in $IMAGE_LABEL; do
			labels="$labels -l $label"
		done

		if [ -z "$IMAGE_NAME" ] || [ -z "$COMMAND_LINE" ]; then
			msg_error "$f: No image name or command line set"
			continue
		fi

		local has_images=$(echo $running_images|grep $IMAGE_NAME|wc -l)
		if [ "$has_images" != "1" ]; then
			msg "Start container $IMAGE_NAME"

			if [ ! -z "$PRE_COMMAND" ]; then
				$PRE_COMMAND || msg_error "Failed to execute pre-command $PRE_COMMAND"
			fi
			docker run -d --name $IMAGE_NAME $labels $COMMAND_LINE || msg_error "Failed to start $IMAGE_NAME"
		else
			msg "Skip already running container $IMAGE_NAME"
		fi
	done
}

for i in 1 2 3 4 5 6 7 8 9 10; do
	if [ -S /var/run/docker.sock ]; then
		start_container
		sv stop start_containers
		exit 0
	fi
	msg "Wait for Docker daemon... $((10-$i))"
	sleep 2
done

msg_error "Docker daemon not found"
sv stop start_containers
