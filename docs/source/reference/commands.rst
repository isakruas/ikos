=================
Command reference
=================

Every shell command, grouped by area. Path arguments may be relative or
absolute and accept ``.`` and ``..``; paths cross mount points transparently.
Names are at most 8 characters (longer names are truncated); input lines are at
most 62 characters. Hexadecimal output is upper-case and unpadded. On any error
a command prints ``?``.

Command names are short on purpose. The full set, by area:

* **System / process:** ``ps`` ``up`` ``slp`` ``cls`` ``say`` ``kill``
* **Filesystem:** ``pwd`` ``cd`` ``ls`` ``mkd`` ``new`` ``cat`` ``rm`` ``cp``
  ``mv`` ``fmt`` ``mnt`` ``umnt`` (plus ``>`` / ``>>`` redirection)
* **Memory / I/O:** ``peek`` ``poke`` ``sbi`` ``cbi`` ``spi`` ``i2c`` ``adc``
* **Scripting:** ``set`` ``if`` ``rep`` ``run``

System and process
==================

``ps``
   One line per live process: its pid and a state letter (``R`` ready,
   ``X`` running, ``S`` sleeping).

``up``
   Print ``T:`` followed by the Timer0 tick count since boot.

``slp <ticks>``
   Put the current (shell) process to sleep for ``<ticks>`` timer ticks,
   yielding the CPU to other processes meanwhile. See
   :doc:`/reference/config` for the tick period.

``cls``
   Clear the screen (emits the ANSI clear/home escape).

``say <text>``
   Print ``<text>`` followed by a newline, expanding ``$var`` references first.
   This is the kernel's "echo": it is the command you redirect into files to
   build scripts, e.g. ``say sbi 0x38 0 >> /init``.

``kill <pid>``
   Stop process ``<pid>``. Out-of-range pids are rejected.

Filesystem
==========

``pwd``
   Print the working directory.

``cd [path]``
   Change directory; ``cd`` with no argument returns to the root.

``ls [path]``
   List a directory and everything under it as a tree, with Unix-style ASCII
   branch connectors. The working directory is used by default.

``mkd <name>`` / ``new <name>``
   Make a directory / create an empty file.

``cat <path>``
   Print a file's contents.

``rm <path>``
   Delete a node. A non-empty directory is removed recursively (its whole
   subtree). The wildcard forms ``rm <dir>/*`` (and ``rm /*``) wipe a
   directory's contents but keep the directory itself.

``cp <file> <dir>`` / ``mv <node> <dir>``
   Copy a file into a directory / move a node into a directory. Both may cross
   between devices (a cross-device move copies then deletes).

``fmt [dev]``
   Wipe a whole volume and re-create an empty root. With no argument it formats
   the internal EEPROM (device 0) and re-creates ``/init``; ``fmt 2`` formats
   the external I2C volume. Use it to clear stale data from the (non-volatile)
   storage.

``mnt <dev> <path>`` / ``umnt <path>``
   Mount block device ``<dev>`` at directory ``<path>``, formatting it if blank
   / unmount it. Device 0 is the internal root filesystem; device 2 is the
   external I2C EEPROM.

``<cmd> > <path>`` / ``<cmd> >> <path>``
   Redirect a command's output to a file — ``>`` overwrites (truncates first),
   ``>>`` appends. The file is created if missing, on the resolved device.

Memory and I/O
==============

``peek <addr>``
   Read and print one byte at a data-space address (hexadecimal). Works on any
   register or SRAM byte.

``poke <addr> <val>``
   Write the whole byte ``<val>`` to ``<addr>``. This replaces all 8 bits — to
   change a single bit without disturbing the rest, use ``sbi`` / ``cbi``.

``sbi <addr> <bit>`` / ``cbi <addr> <bit>``
   Set / clear a single bit (0–7) of the byte at ``<addr>`` via a
   read-modify-write, preserving the other seven bits. This is how you drive one
   GPIO pin without touching the rest of the port, e.g. ``sbi 0x37 0`` (make PB0
   an output) then ``sbi 0x38 0`` / ``cbi 0x38 0`` (PB0 high / low). See
   :doc:`/reference/config` for the port register addresses.

``spi <byte>``
   Full-duplex SPI transfer of one byte; prints the byte read back as ``0x..``.

``i2c w <addr> <byte>`` / ``i2c r <addr>``
   I2C write one byte to / read one byte from a 7-bit address.

``adc <ch>``
   Run one ADC conversion on channel ``<ch>`` and print the 10-bit result
   (0–1023).

Scripting
=========

``set <a-z> <expr>``
   Assign a variable. ``<expr>`` mixes literals and ``$var`` with ``+ - * /``,
   evaluated left to right (no precedence).

``if <a> <op> <b> <cmd>``
   Run ``<cmd>`` if the comparison holds. ``<op>`` is one of ``eq ne lt le gt
   ge`` (chosen so it never clashes with ``>`` / ``<`` redirection).

``rep <n> <cmd>``
   Run ``<cmd>`` ``n`` times (capped at 1000).

``run <path> [&]``
   Run a file as a script, one command per line. ``&`` runs it as a background
   process so the shell stays responsive. The kernel automatically runs
   ``/init`` at boot this way, which makes it the place for startup customisation
   (see :doc:`/reference/examples`).

See :doc:`/guide/scripting` for the expression language and limits, and
:doc:`/reference/examples` for worked shell and integration examples.
