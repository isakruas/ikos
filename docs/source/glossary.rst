========
Glossary
========

.. glossary::

   block device
      A flat, byte-addressable backing store the filesystem runs on. ikOS has
      three: two on-chip EEPROM partitions and one external I2C EEPROM.

   cooperative scheduling
      A process keeps the CPU until it voluntarily yields (waits for input,
      sleeps, or exits). ikOS does not preempt running processes.

   location
      A packed 16-bit value ``device * 256 + node`` naming a filesystem node on
      a specific device. The working directory and the mount table store
      locations.

   mount
      Grafting one block device's directory tree onto a directory of another so
      paths can cross between devices.

   node
      A fixed-size filesystem record: a file or a directory. A device has a
      fixed number of nodes (8 on an internal partition, 64 on the external
      EEPROM).

   process slot
      One of the ``NPROC`` (3) entries in the process table. The shell occupies
      one; background jobs take the others.

   redirection
      Sending a command's output to a file with ``>`` (overwrite) or ``>>``
      (append) instead of to the UART.

   tick
      One Timer0 compare-match interrupt. Ticks drive ``uptime`` and time-based
      sleeps; they do not preempt.

   yield
      A syscall that returns the CPU to the scheduler so another ready process
      can run.
