# OHX Root FS

This directory structure is located on its own partition and is read/write mounted on /var.
All OHX specific directories and files are located in ./ohx.

## Container start up

Container are expected to be started with Dockers "--restart always", so the software
container system will restart containers, also on reboots.

The very first time though, a pre-provisioned image requires start arguments.
This could happen via Docker compose files for example.
Because of the python dependency, docker compose is not available though.
Instead the docker cli command line is stored in a numbered file, eg "01_portainer.sh".
Files are processed in order.

Such a file contains two shell variables IMAGE_NAME and COMMAND_LINE:
```sh
IMAGE_NAME="portainer"
COMMAND_LINE="-p 9000:9000 -p 8000:8000 -v /var/run/docker.sock:/var/run/docker.sock portainer/portainer"

IMAGE_LABEL="hide"
PRE_COMMAND="mkdir -p /var/portainer"
```

*IMAGE_NAME* corresponds to the `--name` command line argument and defines the container name.
*COMMAND_LINE* should not contain "-d", the name or a restart policy. Those are added automatically.

The container may require some filesystem changes. Add those to the optional `PRE_COMMAND`.
You can add labels via the optional *IMAGE_LABEL* variable.

The init system will first check if a container with the given name has already been started.
If not it will execute the following command for the example above:

```sh
docker run -d -l hide -p 9000:9000 -p 8000:8000 --name portainer --restart always -v /var/run/docker.sock:/var/run/docker.sock portainer/portainer
```

## File access
* Only root can access the "container_firststart" directory.
* The "ohx/config" directory belongs to the "OHX" user.
  Each Addon gets an own user. OHX will create a configuration subdirectory for each Addon
  and bind mount it to the respective software container. An ext4 quota limits the available space.
* The "backups" directory is only accessible by the "backup" user.
