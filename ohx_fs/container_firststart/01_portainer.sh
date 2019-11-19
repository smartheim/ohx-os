export IMAGE_NAME="portainer"
export COMMAND_LINE="-p 9000:9000 -p 8000:8000 -v /var/run/docker.sock:/var/run/docker.sock -v /var/portainer:/data portainer/portainer -H unix:///var/run/docker.sock -l service=hide --no-snapshot --admin-password-file /data/admin_password"
export IMAGE_LABEL="service=hide"
export PRE_COMMAND="mkdir -p /var/portainer"
