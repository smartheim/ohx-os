# OHX Root FS

This directory structure is located on its own partition and is read/write mounted on /var.
All OHX specific directories and files are located in ./ohx.

## File access
* Only root can access the "provisioning" directory.
* Anybody can access "cache" and "var".
  Individual files in there might belong to specific users or groups though.
  The system will clear the cache on every boot.
* The "config" directory belongs to the "OHX" user.
  Each Addon gets an own user. OHX will create a configuration subdirectory for each Addon
  and bind mount it to the respective software container.
* The "backups" directory is only accessible by the "backup" user.
