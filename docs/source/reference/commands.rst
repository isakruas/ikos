=================
Command reference
=================

Every shell command. Path arguments may be relative or absolute and accept
``.`` and ``..``. Names are at most 8 characters; input lines at most 62.
Hexadecimal output is upper-case and unpadded. On error a command prints ``?``.

System and shell
================

``help``
   List the available commands.

``ps``
   One line per live process: its pid and state letter (``R`` ready, ``X``
   running, ``S`` sleeping).

``uptime``
   Print ``T:`` followed by the Timer0 tick count since boot.

``mem``
   Print ``P: n/3`` — how many of the three process slots are in use.

``echo <text>``
   Print ``<text>``, expanding ``$var`` references first.

``clear``
   Clear the screen (emits the ANSI clear/home escape).

``kill <pid>``
   Stop process ``<pid>``. Out-of-range pids are rejected.

Filesystem
==========

``pwd``
   Print the working directory.

``cd [path]``
   Change directory; ``cd`` with no argument returns to the root.

``ls [path]``
   List a directory (the working directory by default). Directories show a
   trailing ``/``; files show their byte length.

``tree``
   Print the directory tree from the root using Unix-style ASCII connectors.

``mkdir <name>`` / ``new <name>``
   Make a directory / create an empty file.

``cat <path>``
   Print a file's contents.

``rm <path>``
   Delete a file or an empty directory.

``<cmd> > <path>`` / ``<cmd> >> <path>``
   Redirect a command's output to a file — ``>`` overwrites, ``>>`` appends. The
   file is created if missing, on the resolved device.

``cp <file> <dir>`` / ``mv <node> <dir>``
   Copy a file into a directory / move a node into a directory. Both may cross
   between devices.

``mount <dev> <path>`` / ``umount <path>``
   Mount block device ``<dev>`` (0–2) at directory ``<path>``, formatting it if
   blank / unmount it.

Hardware
========

``peek <hex>``
   Read and print one byte of SRAM at a hexadecimal address.

``poke <hex> <hex>``
   Write a byte (second argument) to an SRAM address (first argument).

``pin <b|c|d><0-7> <0|1>``
   Drive a GPIO pin on port B, C, or D high or low.

``spi <hex>``
   Full-duplex SPI transfer of one byte; prints the byte read back.

``i2c w <addr> <byte>`` / ``i2c r <addr>``
   I2C write one byte to / read one byte from a 7-bit address.

``adc <0-7>``
   Run one ADC conversion on a channel and print the 10-bit result (0–1023).

Scripting
=========

``set <a-z> <expr>``
   Assign a variable. ``<expr>`` mixes literals and ``$var`` with ``+ - * /``,
   evaluated left to right (no precedence).

``if <a> <op> <b> <cmd>``
   Run ``<cmd>`` if the comparison holds. ``<op>`` is one of ``eq ne lt le gt
   ge`` (chosen so it never clashes with ``>`` / ``<`` redirection).

``repeat <n> <cmd>``
   Run ``<cmd>`` ``n`` times.

``run <path> [&]``
   Run a file as a script, one command per line. ``&`` runs it as a background
   process.

See :doc:`/guide/scripting` for the expression language and limits.
