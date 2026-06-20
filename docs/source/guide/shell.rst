=========
The shell
=========

On reset the kernel initialises its subsystems (console, memory, scheduler,
timer, filesystem), prints a banner, and drops into an interactive shell on the
UART:

.. code-block:: text

   ikOS v0.1.0-dev1
   (C) 2026 The ikOS Authors  GPL-3.0-or-later

   ikOS. type 'help'.
   $

The shell is process 0. It reads a line, runs it, and prints the prompt again.
While waiting for input it yields the CPU so other processes run (see
:doc:`processes`). ``help`` lists every command; the full set is in
:doc:`/reference/index`.

Line editing
============

Input is line-buffered. A line is submitted on carriage return; backspace
deletes the last character. Lines are at most 62 characters. The prompt shows
the working directory followed by ``$``.

The filesystem
==============

Files live in a directory tree. The disk starts empty — you create everything.
Path arguments may be relative or absolute and accept ``.`` and ``..``.

.. code-block:: text

   $ mkdir etc
   $ cd etc
   $ pwd
   /etc
   $ new motd
   $ cd /
   $ ls
   etc/

Directories list with a trailing ``/``; files list with their byte length.

Writing files: redirection
===========================

There is no ``append`` command. A command's output is written to a file with
redirection — ``>`` truncates and writes, ``>>`` appends. The target file is
created if it does not exist, anywhere in the tree (including on a mounted
volume):

.. code-block:: text

   $ echo hello >> motd      # create/append
   $ cat motd
   hello
   $ echo world > motd       # overwrite
   $ cat motd
   world

``tree``
========

``tree`` draws the same connectors as the Unix ``tree`` (ASCII charset):

.. code-block:: text

   |--      a child with siblings below it
   `--      the last child
   |        continue an ancestor column
   (blank)  close an ancestor column

.. code-block:: text

   $ tree
   /
   `-- etc/
       `-- motd

Hardware from the shell
=======================

The serial buses and GPIO are reachable directly:

.. code-block:: text

   $ pin b5 1          # drive PORTB5 high
   $ spi 41            # full-duplex SPI transfer of 0x41, prints the byte read back
   $ i2c w 50 0a       # write 0x0A to I2C device 0x50
   $ i2c r 50          # read one byte from 0x50
   $ adc 0             # 10-bit conversion on ADC channel 0 (0..1023)

Raw memory is available with ``peek``/``poke`` (hexadecimal address and byte).
Hex output is upper-case and unpadded.
