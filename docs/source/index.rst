=====================
ikOS Reference Manual
=====================

**ikOS** is a small multitasking kernel for 8-bit Atmel/Microchip **AVR**
microcontrollers, written in the **ik** language and built with the **ik8b**
toolchain. It boots into an interactive shell over the UART, with a tiny
scripting language, a hierarchical filesystem on the on-chip EEPROM, and
commands for files, processes, memory, GPIO, and the serial buses
(UART/SPI/I2C/ADC).

It targets the ``atmega32`` and ``atmega328p`` out of the box and fits in
32 KB of flash with a few hundred bytes of SRAM. Scheduling is **cooperative**:
each process runs until it yields, and a Timer0 tick drives ``up`` and timed
sleeps. ikOS is not a hard real-time OS — there is no preemption or priority
scheduling.

This manual is organised into three parts: a **user guide** (build it, drive the
shell, write scripts, use storage), a **kernel internals** section (boot,
scheduler, memory map, filesystem, drivers), and a **reference** (the full
command set).

.. rubric:: Meet Iki

**Iki** is the ikOS mascot — an ant.

Why an ant? Ants are tiny, yet together they accomplish feats far beyond their
size: they carry many times their own weight, build, forage, and defend as one.
They manage it through cooperation and union — no ant is in charge; each does its
small part and yields to the colony. ikOS works the same way: a kernel small
enough to fit in 32 KB, where processes are scheduled *cooperatively*, each
yielding the CPU to the others so that, together, the little system does real
work. Small, collaborative, capable — that is Iki.

.. code-block:: text

        \   /
        (o o)
     ==(=======)==
        / | | \

.. rubric:: A first session

.. code-block:: text

   ikOS 0.1.0 Sauva GPL-3.0+
   /$ mkd etc
   /$ cd etc
   /$ say hello >> motd
   /$ cat motd
   hello
   /$ cd /
   /$ ls
   /
   `-- etc/
       `-- motd

.. toctree::
   :maxdepth: 2
   :caption: User guide

   guide/index

.. toctree::
   :maxdepth: 2
   :caption: Kernel internals

   internals/index

.. toctree::
   :maxdepth: 2
   :caption: Reference

   reference/index

.. toctree::
   :maxdepth: 1
   :caption: Appendix

   glossary

Indices and tables
==================

* :ref:`genindex`
* :ref:`search`
