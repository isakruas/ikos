==============
Boot and init
==============

``boot.ik`` is the entry point. ``@main`` initialises each subsystem in order,
starts the shell as process 0, enables interrupts, and hands control to the
scheduler, which never returns.

.. code-block:: text

   @main {
       @uart_init(UART_UBRR)            # console up
       @kbanner()                       # print the banner
       @bss_clear()                     # zero the kernel data region
       @sched_init()                    # mark every process slot free
       @timer_init()                    # start the Timer0 tick
       ? @fs_blank(DEV_ROOT) == 1 { @fs_format(DEV_ROOT) }
       @proc_start(0, &@shell_main)     # admit the shell as pid 0
       @sei()                           # enable interrupts
       @scheduler()                     # run forever
   }

Order matters: ``@bss_clear`` zeroes the kernel state region (``0x0400`` upward)
before any subsystem writes to it, and the root filesystem is formatted only if
the EEPROM does not already hold a valid tree, so data survives a reset.

.. function:: @kbanner()

   Print the boot banner — the name, version, copyright, and license — to the
   UART. It is intentionally compact to save flash.

.. function:: @bss_clear() -> u8

   Zero the kernel data region (``BSS_BASE`` for ``BSS_LEN`` bytes) so every
   subsystem starts from a known state; SRAM is not cleared by reset.

Per-target timer
================

``arch/timer.ik`` is a small hardware abstraction layer. Each supported device
gets a ``? target == ...`` block that programs Timer0 in CTC mode with a
1024 prescaler and enables the compare-match interrupt:

.. function:: @timer_init()

   Configure Timer0 for a periodic compare-match interrupt. The matching ISR,
   ``TIMER0_COMPA``, increments the global tick counter read by ``uptime``.

Adding another AVR is mostly a matter of adding its timer block here.
