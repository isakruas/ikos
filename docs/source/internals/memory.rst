===========
Memory maps
===========

This page covers both volatile memory (the SRAM layout the kernel lays out by
hand) and the on-disk format of the EEPROM filesystem.

SRAM startup
============

The AVR does **not** clear RAM on reset, so the compiler emits a small crt0-style
routine that zeroes the whole SRAM before ``@main`` runs. That makes a program
start from the same controlled state on real silicon as it does in the
simulator (whose RAM is already zero), so every global begins life at zero.

The SRAM map
============

``kernel/memory.ik`` lays out SRAM by hand. The map is chosen to fit **both**
the ATmega32 (RAM ``0x0060``–``0x085F``) and the ATmega328p
(``0x0100``–``0x08FF``): kernel state sits at ``0x0340`` — above the compiler's
statics on either part — and process stacks fill up to ``0x07FF``, leaving
``0x0800``–RAMEND for the scheduler/reset stack on whichever device.

=================== ====================================================
Range               Contents
=================== ====================================================
``..0x033F``        compiler statics (ATmega32 from ``0x0060``)
``0x0340..0x0565``  kernel state (zeroed at boot; ``BSS_LEN = 0x0226``)
``0x0566..0x07FF``  process stacks (no overlap with kernel state)
``0x0800..RAMEND``  scheduler / reset stack
=================== ====================================================

Kernel state
============

The kernel data region holds, in order: the process table (state, saved SP, and
wake tick per pid), the ``ls`` tree renderer's per-depth connector flags, the
scheduler's saved SP / current-pid / tick counter, the 26 script variables and
the lazy bus-init and redirection flags, the shell's line and expansion buffers,
the two-slot mount table, the script/working scratch buffers, and the per-pid
background-job state.

============== =========== ===================================================
Symbol         Address     Role
============== =========== ===================================================
``PROC_STATE`` ``0x0340``  per-pid state byte
``PROC_SP``    ``0x0344``  per-pid saved stack pointer
``PROC_WAKE``  ``0x034C``  per-pid wake tick while sleeping
``TICKS``      ``0x0364``  tick counter from the Timer0 ISR (``up``)
``VARS``       ``0x0368``  the 26 script variables ``a``–``z``
``CWD_LOC``    ``0x039E``  working directory as a packed ``(device, node)``
``LINE_BUF``   ``0x03A0``  current input line (64 bytes)
``EXPAND``     ``0x03E8``  line after ``$var`` expansion (80 bytes)
``MNT_*``      ``0x0438``  two-slot mount table (used / device / mountpoint)
``SCRATCH``    ``0x0440``  script-line / file working buffer
``BG_FILE``    ``0x04E0``  per-pid background script location
============== =========== ===================================================

Process stacks
==============

Each process gets a fixed stack that grows downward; pid 0 (the shell) gets the
most room. The three tile ``0x0566``–``0x07FF`` with no gaps and no overlap with
the kernel state below:

========= ================ ==========
Process   Top              Size
========= ================ ==========
pid 0     ``0x07FF``       320 B
pid 1     ``0x06BF``       160 B
pid 2     ``0x061F``       186 B
========= ================ ==========

The EEPROM filesystem layout
============================

Each block device holds the same tree, but file data is allocated dynamically
from a shared cluster pool (a FAT-style allocator), so a file grows to whatever
free space allows instead of a fixed per-file slot.

A **node** is 16 bytes:

=========== ====================================================
Bytes       Field
=========== ====================================================
``[0]``     type (0 free, 1 file, 2 dir)
``[1]``     parent node index
``[2..3]``  length (u16)
``[4..11]`` name (8 bytes, NUL-padded)
``[12]``    first cluster (``0xFF`` = empty file)
=========== ====================================================

The internal volume (device 0) uses the whole 1 KB on-chip EEPROM, laid out as
the node table, then the FAT (one next-pointer byte per cluster; ``0xFF`` free,
``0xFE`` end-of-chain), then the data clusters:

=================== ====================================================
Range (in device)   Contents
=================== ====================================================
``0x000..0x07F``    node table (8 nodes × 16 B)
``0x080..0x0B3``    FAT (52 cluster pointers)
``0x0B4..0x3F3``    data (52 clusters × 16 B) — files up to ~832 B
=================== ====================================================

The external I2C EEPROM (device 2) uses 64 nodes with fixed 256-byte slots.

A packed location
=================

A filesystem location is a 16-bit value ``device * 256 + node``. ``CWD_LOC`` and
the mount table store locations this way, so a path can name a node on any
device and crossing a mount point is just following the location to a different
device. The helpers ``@loc``, ``@loc_dev``, and ``@loc_node`` pack and unpack
them.
