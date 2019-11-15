# OHX Root FS

This directory structure is located on its own partition and is read/write mounted.

## First Boot Provisioning

Some software packages and containers need to be installed and some scripts to be started on the very first boot.
Those can be found in the "provisioning" directory.

As soon as all software packages are installed
and docker containers imported a file "done" is created within that directory.
The startup service will not perform those actions again when that file is found.

## File access
* Only root can access the "provisioning" directory.
* Anybody can access "cache" and "var".
  Individual files in there might belong to specific users or groups though.
  The system will clear the cache on every boot.
* The "config" directory belongs to the "OHX" user.
  Each Addon gets an own user. OHX will create a configuration subdirectory for each Addon
  and bind mount it to the respective software container.
* The "backups" directory is only accessible by the "backup" user.
