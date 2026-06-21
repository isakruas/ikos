========
Examples
========

Worked shell sessions and integration recipes. Lines starting with the prompt
``/$`` are what you type; the lines under them are what the kernel prints.

Shell basics
============

Filesystem
----------

.. code-block:: text

   /$ mkd logs
   /$ say hello >> logs/a
   /$ cat logs/a
   hello
   /$ ls
   /
   `-- logs/
       `-- a
   /$ cp logs/a logs            # (cp/mv take a target directory)
   /$ rm logs/*                 # wipe the directory's contents, keep logs/
   /$ rm logs                   # remove the now-empty directory

Variables, arithmetic and conditionals
---------------------------------------

.. code-block:: text

   /$ set x 5
   /$ set y $x + 3 * 2          # left-to-right, no precedence -> (5+3)*2 = 16
   /$ say $y
   16
   /$ if $y gt 10 say big
   big
   /$ rep 3 say hi
   hi
   hi
   hi

GPIO from the shell
===================

Registers are addressed directly (see :doc:`/reference/config`). ``sbi`` / ``cbi``
flip one bit without disturbing the rest of the port; ``poke`` writes a whole
byte.

.. code-block:: text

   /$ sbi 0x37 0     # DDRB bit0 = output
   /$ sbi 0x38 0     # PB0 high
   /$ cbi 0x38 0     # PB0 low
   /$ peek 0x36      # read PINB (the input levels)
   01

Reading an analog input
=======================

.. code-block:: text

   /$ adc 0          # one conversion on channel 0
   512
   /$ peek 0x25      # ADCH after the conversion (512 = 0x0200)
   2

Startup customisation with /init
================================

The kernel runs ``/init`` automatically at boot, as a background-capable script
(one command per line). Because the storage is non-volatile EEPROM, edits
persist across resets. Build it from the shell by redirecting ``say`` into it::

   /$ say sbi 0x37 0   >> /init
   /$ say say booted   >> /init
   /$ cat /init
   sbi 0x37 0
   say booted
   /$ run init          # run it now (also runs at every boot)
   booted

``/init`` is the integration hook: put any commands there to set pin states,
launch background jobs, print a banner, mount a volume, and so on. To start
over, ``fmt`` wipes the disk and re-creates an empty ``/init``.

Blinking an LED in the background
=================================

A script runs once, top to bottom — there is no infinite loop keyword — but a
script can **re-launch itself** as a background process, and ``slp`` yields the
CPU so the shell stays responsive. That gives a continuous blinker on **PB0**.

``/blink`` (one blink, then re-launch itself)::

   /$ say sbi 0x38 0     >> /blink
   /$ say slp 20         >> /blink
   /$ say cbi 0x38 0     >> /blink
   /$ say slp 20         >> /blink
   /$ say run /blink &   >> /blink

``/init`` (make PB0 an output, launch the blinker in the background)::

   /$ say sbi 0x37 0     >> /init
   /$ say run /blink &   >> /init

Reboot (or ``run init``) and PB0 blinks forever while the shell keeps working.
``slp 20`` is ~20 ticks (~0.25 s at the default 8 MHz / prescaler-1024 timer);
raise it to blink slower. To stop, ``fmt`` or re-create ``/blink`` without the
trailing ``run /blink &``.

.. note::

   The ``&`` is what makes ``run /blink`` background. Without it the boot would
   block forever inside the blinker and the shell would never appear.

Running scripts from external EEPROM
====================================

``/init`` itself must live on the internal disk (it runs before any mount), but
it can mount the external I2C EEPROM and run a script from there — handy because
the external device survives reflashing the firmware and holds far more.

``/init`` (internal)::

   sbi 0x37 0
   mnt 2 /ext
   run /ext/blink &

Create ``/ext/blink`` once, after mounting::

   /$ mnt 2 /ext
   /$ say sbi 0x38 0     >> /ext/blink
   /$ say slp 20         >> /ext/blink
   /$ say cbi 0x38 0     >> /ext/blink
   /$ say slp 20         >> /ext/blink
   /$ say run /ext/blink & >> /ext/blink

``mnt`` only formats the volume when it is blank, so an existing ``/ext/blink``
is left intact across reboots. The external EEPROM is slower (TWI, byte by byte)
than the internal one.

Serial buses
============

.. code-block:: text

   /$ spi 41         # full-duplex transfer of 0x41
   0x42
   /$ i2c w 50 05    # write byte 0x05 to I2C address 0x50
   ok
   /$ i2c r 50       # read one byte from 0x50
   0x..
