================
Building ikOS
================

ikOS is a set of ``.ik`` source files compiled to a single Intel HEX image by
the **ik8b** toolchain. The entry point and import graph are rooted at
``boot.ik``.

Prerequisites
=============

* The toolchain, vendored as a submodule at ``tools/ikide`` (the IKIDE tree,
  which bundles the ``ik8b`` compiler and its standard library). After cloning,
  populate it and build the compiler binary once::

     git submodule update --init --recursive
     make toolchain

Build and run
=============

From the ikOS directory, everything runs through ``make``:

.. code-block:: sh

   make build            # compile to build/boot.hex
   make run              # compile and simulate (LIMIT=N overrides the cap)
   make test             # run the end-to-end shell test harness
   make docs             # build this manual

``make`` invokes the submodule's ``ik8b`` with ``IK8B_STD_PATH`` set so the
``import kernel/...`` paths and the standard library resolve, and writes the
image to ``build/boot.hex``. ``run`` additionally simulates the image in the
ik8b/ik8bvm simulator.

Drive the shell over the UART at **9600 baud** (8N1). In the IKIDE breadboard,
the UART tab speaks to the running image directly.

Choosing the target
====================

The device is selected by the ``target`` declaration at the top of ``boot.ik``:

.. code-block:: text

   target atmega328p

``atmega32`` and ``atmega328p`` are supported out of the box. The SRAM map in
``kernel/memory.ik`` is chosen to fit both, and ``arch/timer.ik`` is a small
per-target HAL — a ``? target == ...`` block per device that programs Timer0.
Porting to another classic AVR means adding its timer block there (and, if its
ADC registers differ, the addresses used by the ``adc`` command).

Footprint
=========

The image is tight: it fills nearly all of the 32 KB flash and uses a few
hundred bytes of SRAM. ``make build`` prints a usage report (flash, SRAM,
EEPROM) after each build; watch it when adding features.
