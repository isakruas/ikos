================
The filesystem
================

The filesystem is three layers: a **block** device abstraction
(``fs/block.ik``), a **mount** table (``fs/mount.ik``), and the hierarchical
**tree filesystem** (``fs/treefs.ik``) that runs on top of any block device.

Block devices
=============

``fs/block.ik`` exposes byte read/write to three devices and hides where the
bytes actually live:

* devices **0** and **1** are the low and high 512-byte halves of the on-chip
  EEPROM, reached with ``@eeprom_read`` / ``@eeprom_write`` at a partition
  offset;
* device **2** is an external 24Cxx I2C EEPROM at ``0x50``, reached over the TWI
  bus with a 16-bit word address.

.. function:: @blk_read($dev: u8, $addr: u16) -> u8

   Read one byte at ``$addr`` within device ``$dev``.

.. function:: @blk_write($dev: u8, $addr: u16, $val: u8)

   Write one byte at ``$addr`` within device ``$dev``.

On-disk layout
==============

Each device holds a flat array of fixed-size **nodes** followed by a data
region. A node is ``FS_NODESZ`` (12) bytes: a type byte (free / file /
directory), a parent node index, a 16-bit length, and an 8-byte name
(``FS_NAMELEN``). Node 0 is the device's root directory. Geometry is per device:
the internal partitions hold 8 nodes with 50-byte data blocks; the external
EEPROM holds 64 nodes with 256-byte blocks.

.. function:: @fs_format($dev: u8)

   Initialise ``$dev`` as an empty filesystem: clear the node table and make
   node 0 a directory.

.. function:: @fs_mknode($dev: u8, $parent: u16, $name: ptr ram u8, $type: u8) -> u16

   Allocate a node under ``$parent`` with ``$name`` and ``$type``, and return
   its **node index** (not a packed location). Returns ``0xFFFF`` if the name
   already exists or the device is full.

.. function:: @fs_resolve($path: u16, $start: u16) -> u16

   Resolve a path (absolute from the root, or relative to ``$start``) to a
   packed ``(device, node)`` location, crossing mount points. Returns
   ``0xFFFF`` if it does not exist.

.. note::

   ``@fs_mknode`` returns a bare node index. Callers that need a location must
   pack it with the node's device — ``@loc(dev, node)`` — before treating it as
   one.

Mounting
========

``fs/mount.ik`` keeps a small table mapping a directory (a packed location) to a
device whose root tree is shown there. Path resolution consults it so a path can
descend from one device into another. ``@mount_add`` and ``@mount_remove_dev``
manage the table; ``@mount_mp_of`` finds where a device is mounted.

Redirection target
==================

Output redirection (``>`` / ``>>``) resolves the target path, creating the file
if needed on the resolved device, and stores the destination device and node in
``REDIRECT_DEV`` / ``REDIRECT_NODE``. While redirection is active every console
byte is appended to that file via ``@fs_append_byte`` instead of going to the
UART.
