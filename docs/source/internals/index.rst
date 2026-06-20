================
Kernel internals
================

How ikOS is put together: the boot sequence, the cooperative scheduler and
syscalls, the SRAM map, the filesystem stack, and the device drivers. This part
follows the source layout under ``boot.ik``, ``arch/``, ``kernel/``, ``fs/``,
``drivers/``, and ``shell/``.

.. toctree::
   :maxdepth: 1

   boot
   scheduler
   cpu
   memory
   filesystem
   drivers
