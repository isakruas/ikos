=======
Drivers
=======

Device access is split between a console driver (``drivers/serial.ik``) and the
serial-bus commands (``drivers/bus.ik``). The kernel uses the ik8b standard
library (``std/uart``, ``std/spi``, ``std/twi``, ``std/eeprom``, ``std/conv``)
for the register-level primitives and adds thin shell-facing wrappers.

Console (UART)
==============

``drivers/serial.ik`` owns the console. ``@putc`` is the single output choke
point: when redirection is active it appends the byte to a file (see
:doc:`filesystem`), otherwise it transmits over the UART. Higher-level helpers
build on it.

.. function:: @putc($c: u8)

   Emit one byte — to the active redirection target if set, else to the UART.

.. function:: @puts($s: str ram)

   Emit a NUL-terminated string with ``@putc``.

.. function:: @put_u16($v: u16)

   Print ``$v`` in decimal (via ``std/conv``'s ``@utoa``).

.. function:: @put_hex($v: u16)

   Print ``$v`` in upper-case hexadecimal, unpadded.

GPIO, SPI, I2C
==============

GPIO is done straight from the shell with ``sbi`` / ``cbi`` (single-bit
read-modify-write) and ``poke`` / ``peek`` on the port registers, so no GPIO
driver is needed (see :doc:`/reference/config` for the register map). The
``spi`` and ``i2c`` commands wrap ``std/spi`` and ``std/twi``: SPI is initialised
in master mode on first use; the I2C commands drive a single read or write
transaction against a 7-bit address.

ADC
===

The ``adc`` command performs one classic-ADC conversion on a channel and prints
the 10-bit result. It selects the channel, starts the conversion, polls the
``ADSC`` bit until the conversion completes, and reads ``ADCL`` then ``ADCH``.

.. function:: @cmd_adc($arg: u16)

   Parse a channel (0–7), run a conversion, and print the value (0–1023).

Buses and storage together
==========================

Because the filesystem's device 2 lives on the same TWI bus as the ``i2c``
command, an external 24Cxx EEPROM can serve both as a mountable volume and as a
target for raw ``i2c`` transactions.
