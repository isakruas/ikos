==============
Boot and init
==============

``boot.ik`` is the entry point. ``@main`` initialises each subsystem in order,
seeds and runs the ``/init`` script, starts the shell as process 0, arms the
watchdog, enables interrupts, and hands control to the scheduler, which never
returns.

.. code-block:: text

   @main {
       %WDT_STATUS_REG & 0xF7 -> %WDT_STATUS_REG   # clear the WDT reset flag
       @wdt_disable()                   # disable the watchdog for slow init
       @uart_init(UART_UBRR)            # console up
       @kbanner()                       # print the banner
       @sched_init()                    # mark every process slot free
       @timer_init()                    # start the Timer0 tick
       ? @fs_blank(DEV_ROOT) == 1 { @fs_format(DEV_ROOT) }
       @_seed_init()                    # create /init if missing
       @proc_start(0, &@shell_main)     # admit the shell as pid 0
       @wdt_enable(0x07)                # arm the ~2 s hang-recovery watchdog
       @sei()                           # enable interrupts
       @scheduler()                     # run forever
   }

Order matters. The root filesystem is formatted only if the EEPROM does not
already hold a valid tree, so data survives a reset. The watchdog is disabled
across the slow boot-time init (an EEPROM format is many ~8 ms writes) and armed
only just before the scheduler, which kicks it every pass (see
:doc:`scheduler`).

The kernel does **not** clear SRAM itself: the compiler emits a crt0-style
routine that zeroes the whole SRAM before ``@main`` runs (the AVR does not reset
RAM), so every global starts from a known state. See :doc:`memory`.

.. function:: @kbanner()

   Print the boot banner — the name, version codename, copyright and license —
   to the UART. It is intentionally compact to save flash.

Per-target timer
================

``arch/timer.ik`` is a small hardware abstraction layer. Each supported device
gets a ``? target == ...`` block that programs Timer0 in CTC mode with a
1024 prescaler and enables the compare-match interrupt:

.. function:: @timer_init()

   Configure Timer0 for a periodic compare-match interrupt. The matching ISR,
   ``TIMER0_COMPA``, increments the global tick counter read by ``up``.

Adding another AVR is mostly a matter of adding its timer block here.
