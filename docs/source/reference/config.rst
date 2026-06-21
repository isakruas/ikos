=============================
Configuration & register maps
=============================

``config.ik`` holds the few build-time constants the kernel depends on. Most are
pre-computed numbers (clock speed, the UART divisor); this page is the lookup
table for choosing them, plus the hardware register addresses you reference from
the shell with ``peek`` / ``poke`` / ``sbi`` / ``cbi``.

config.ik
=========

.. code-block:: text

   @cpu_mhz() -> u16 { return 8 }        # CPU clock in MHz
   const NPROC: u8     = 3               # process slots: shell + 2
   const UART_UBRR: u16 = 51             # 8 MHz, 9600 baud  (see table below)

``@cpu_mhz()``
   The CPU clock, in MHz. Drivers that need real time (delays, the UART divisor,
   timer period) read it. **It must match the actual clock** selected by the
   fuses (external crystal or internal RC). A mismatch garbles the UART and
   skews every delay.

``NPROC``
   Number of process slots: the shell (pid 0) plus ``NPROC - 1`` background
   jobs. Each slot costs a fixed stack (see :doc:`/internals/memory`).

``UART_UBRR``
   The USART baud divisor, ``UBRR``. It is **pre-computed** because the AVR has
   no floating point at boot; pick it from the table for your clock and baud.

UART_UBRR table
===============

Normal mode (U2X = 0). The formula is:

.. code-block:: text

   UBRR = round( F_CPU / (16 * baud) ) - 1

================ =========== =========== ===========
Baud             1 MHz       8 MHz       16 MHz
================ =========== =========== ===========
2400             25          207         416
4800             12          103         207
**9600**         6 *(err)*   **51**      103
14400            3 *(err)*   34          68
19200            2 *(err)*   25          51
38400            —           12          25
57600            —           8           16
115200           —           3           8
================ =========== =========== ===========

*(err)* marks combinations whose rounding error is large enough to be unreliable
— prefer a clock that divides the baud cleanly. The kernel default (``51``) is
9600 baud at 8 MHz, which is exact.

GPIO port registers (ATmega32)
==============================

Each port has three registers, addressed in the data space (what ``peek`` /
``poke`` / ``sbi`` / ``cbi`` take):

* ``DDRx`` — direction: bit = 1 makes the pin an **output**, 0 an input.
* ``PORTx`` — output value when an output; the **pull-up** when an input.
* ``PINx`` — reads the pin's input level.

======== ========= ========= =========
Port     ``PINx``  ``DDRx``  ``PORTx``
======== ========= ========= =========
A        ``0x39``  ``0x3A``  ``0x3B``
B        ``0x36``  ``0x37``  ``0x38``
C        ``0x33``  ``0x34``  ``0x35``
D        ``0x30``  ``0x31``  ``0x32``
======== ========= ========= =========

So ``0x38`` is ``PORTB`` and ``0x37`` is ``DDRB``. To drive **PB0** high::

   sbi 0x37 0      # DDRB bit 0 = output
   sbi 0x38 0      # PORTB bit 0 = 1  (PB0 high)
   cbi 0x38 0      # PORTB bit 0 = 0  (PB0 low)

To read an input pin, configure it (``cbi`` its ``DDRx`` bit, optionally ``sbi``
its ``PORTx`` bit for the pull-up) and ``peek`` the ``PINx`` register.

Other useful registers (ATmega32)
=================================

=========== ========= ===================================================
Register    Address   Notes
=========== ========= ===================================================
``ADCL``    ``0x24``  ADC result low byte (read low byte first)
``ADCH``    ``0x25``  ADC result high byte
``SREG``    ``0x5F``  status register (bit 7 = global interrupt enable)
``TCNT0``   ``0x52``  Timer0 counter
``UDR``     ``0x2C``  USART data register
=========== ========= ===================================================

The :doc:`/reference/examples` page shows these registers used from the shell.
