# Resources

Files, scripts and programs in this directory are being used during the image build process.

* growpart.sh: This script is shipped with each image and called during the first boot to resize
  the data partition.
* grub.cfg: For uefi systems this grub configuration file is used.
* runit: This is the name of the init system on void linux and the directory contains
  init scripts to resize the data partition if necessary and perform some ohx first start actions.
* partfs: Used during image creation for user mounting an .img file.
