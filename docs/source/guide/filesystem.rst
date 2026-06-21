=======================
Storage and mounting
=======================

The filesystem is a directory tree stored on a block device. ``mnt`` grafts one
device's tree onto a directory of another so paths can cross between them. File
data is allocated dynamically from a shared cluster pool, so a file grows to
whatever free space allows (see :doc:`/internals/memory` for the on-disk layout).

Devices
=======

============ =========================================== =====================
Device       Backing store                               Capacity
============ =========================================== =====================
``0``        on-chip EEPROM (the root fs, whole 1 KB)    8 nodes, up to ~832 B/file
``2``        external I2C EEPROM (24Cxx) at ``0x50``     64 nodes, 256 B/file
============ =========================================== =====================

Device 0 is the on-chip EEPROM and is mounted at ``/`` automatically. It is
small — **eight nodes total**: the root directory plus seven files or
directories. Device 2 lives on a real 24Cxx part wired to the TWI/I2C bus,
addressed with a 16-bit word address; it is non-volatile across firmware
reflashes and far larger.

Files and directories
=====================

.. code-block:: text

   $ mkd docs
   $ new docs/readme
   $ say hi >> docs/readme
   $ cat docs/readme
   hi
   $ cp docs/readme /            # copy a file into a directory
   $ mv docs/readme /tmpdir      # move a node into a directory (may cross devices)
   $ rm docs                     # remove a node (a directory is removed recursively)

Names are at most **8 characters**. ``cp`` copies a file into a directory;
``mv`` moves any node into a directory; both work across devices. ``rm`` deletes
a file, or a directory and its whole subtree; ``rm <dir>/*`` wipes a directory's
contents but keeps the directory. ``fmt`` wipes a whole volume.

Mounting
========

``mnt <dev> <path>`` formats the device if it is blank, then makes its tree
appear at ``<path>``. ``umnt <path>`` detaches it.

.. code-block:: text

   $ mkd ext
   $ mnt 2 /ext         # the external EEPROM now appears under /ext
   $ say data >> /ext/note
   $ cat /ext/note
   data
   $ umnt /ext          # /ext is an empty directory again
   $ mnt 2 /ext         # remount: the data is still on the device
   $ cat /ext/note
   data

Data written through a mount point lives on the mounted device and persists
across ``umnt``/``mnt`` — and, for the external EEPROM, across reflashing the
firmware.
