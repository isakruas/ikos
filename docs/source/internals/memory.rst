==============
The SRAM map
==============

``kernel/memory.ik`` lays out SRAM by hand. The map is chosen to fit **both**
the atmega32 (RAM ``0x0060``–``0x085F``) and the atmega328p
(``0x0100``–``0x08FF``): kernel data sits at ``0x0400`` — above the compiler's
statics on either part — and process stacks stay below ``0x0700``, so the
scheduler's reset stack can use whatever the device's RAMEND is.

Overview
========

=================== ====================================================
Range               Contents
=================== ====================================================
``..0x03FF``        compiler statics
``0x0400..0x05E3``  kernel state (zeroed at boot by ``@bss_clear``)
``0x05E4..0x07FF``  process stacks
``0x0800..RAMEND``  scheduler / reset stack
=================== ====================================================

The zeroed region is ``BSS_BASE = 0x0400`` for ``BSS_LEN = 0x0226`` bytes.

Kernel state
============

The kernel data region holds, in order: the process table (state, saved SP, and
wake tick per pid), the ``tree`` command's per-depth connector flags, the
scheduler's saved SP / current-pid / tick counter, the 26 script variables and
the lazy bus-init and redirection flags, the shell's line buffer and the
expansion buffer, the two-slot mount table, the script/working scratch buffers,
and the per-pid background-job state.

============== ============================================================
Symbol         Role
============== ============================================================
``PROC_STATE`` per-pid state byte
``PROC_SP``    per-pid saved stack pointer
``PROC_WAKE``  per-pid wake tick while sleeping
``TICKS``      tick counter incremented by the Timer0 ISR (``uptime``)
``VARS``       the 26 script variables ``a``–``z``
``CWD_LOC``    current directory as a packed ``(device, node)`` location
``LINE_BUF``   current input line (64 bytes)
``EXPAND``     line after ``$var`` expansion (80 bytes)
``MNT_*``      two-slot mount table (used / device / mountpoint)
``SCRATCH``    script-line / file working buffer
``BG_FILE``    per-pid background script location
============== ============================================================

Process stacks
==============

Each process gets a fixed stack that grows downward; pid 0 (the shell) gets the
most room:

========= ================ ==========
Process   Top              Size
========= ================ ==========
pid 0     ``0x07FF``       288 B
pid 1     ``0x06DF``       128 B
pid 2     ``0x065F``       124 B
========= ================ ==========

A packed location
=================

A filesystem location is a 16-bit value ``device * 256 + node``. ``CWD_LOC`` and
the mount table store locations this way so a path can name a node on any
device and crossing a mount point is just following the location to a different
device. The helpers ``@loc``, ``@loc_dev``, and ``@loc_node`` pack and unpack
them.
