=======================
Storage and mounting
=======================

The filesystem is a directory tree stored on a block device. ikOS knows three
devices, and ``mount`` grafts one device's tree onto a directory of another so
paths can cross between them.

Devices
=======

============ =========================================== ================
Device       Backing store                               Capacity
============ =========================================== ================
``0``        on-chip EEPROM, low half (the root fs)      8 nodes, 50 B/file
``1``        on-chip EEPROM, high half                   8 nodes, 50 B/file
``2``        external I2C EEPROM (24Cxx) at ``0x50``     64 nodes, 256 B/file
============ =========================================== ================

Devices 0 and 1 are two partitions of the same on-chip EEPROM, so a second
volume is exercisable without any extra hardware. Device 2 lives on a real
24Cxx part wired to the TWI/I2C bus and is addressed with a 16-bit word address.

The root filesystem (device 0) is mounted at ``/`` automatically and is small —
**eight nodes total**, the root directory plus seven files or directories.

Files and directories
=====================

.. code-block:: text

   $ mkdir docs
   $ new docs/readme
   $ echo hi >> docs/readme
   $ cat docs/readme
   hi
   $ cp docs/readme /            # copy a file into a directory
   $ mv docs/readme /tmpdir      # move a node into a directory (may cross devices)
   $ rm docs                     # remove a node (a directory must be empty)

Names are at most **8 characters**. ``cp`` copies a file into a directory;
``mv`` moves any node into a directory; both work across devices. ``rm`` deletes
a file or an *empty* directory.

Mounting
========

``mount <dev> <path>`` formats the device if it is blank, then makes its tree
appear at ``<path>``. ``umount <path>`` detaches it.

.. code-block:: text

   $ mkdir ext
   $ mount 1 /ext       # device 1's filesystem now appears under /ext
   $ echo data >> /ext/note
   $ cat /ext/note
   data
   $ umount /ext        # /ext is an empty directory again
   $ mount 1 /ext       # remount: the data is still on the device
   $ cat /ext/note
   data

Data written through a mount point lives on the mounted device and persists
across ``umount``/``mount``. Mounting device 2 puts the filesystem on the
external I2C EEPROM, driven over the TWI bus.
