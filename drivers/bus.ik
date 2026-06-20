# ikOS - a small multitasking kernel in the ik language for 8-bit AVR.
# Copyright (C) 2026 The ikOS Authors
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
# SPDX-License-Identifier: GPL-3.0-or-later
# Serial-bus commands: SPI transfer and I2C (TWI) read/write. Wraps std/spi and
# std/twi. SPI master is initialised on first use.

@cmd_spi($arg: u16) {
    ? $arg == 0 {
        @eperr()
        return
    }
    ram ptr u8 $f = SPI_READY
    ? *$f == 0 {
        @spi_init_master_raw()
        1 -> *$f
    }
    ram ptr u8 $a = $arg
    ram imut $r: u8 = @spi_transfer(@_hex16($a) & 0xFF)
    @puts("0x")
    @put_hex($r)
    @nl()
}

# adc <0-7>   read a 10-bit conversion (0..1023) from one ADC channel
@cmd_adc($arg: u16) {
    ? $arg == 0 { @eperr() return }
    ram ptr u8 $a = $arg
    ram imut $ch: u8 = @atoi($a) & 0x07
    @adc_init()
    @put_u16(@adc_read($ch))
    @nl()
}

# i2c w <addr> <byte>   write one byte
# i2c r <addr>          read one byte
@cmd_i2c($arg: u16) {
    ? $arg == 0 { @eperr() return }
    ram imut $r1: u16 = @_split($arg)
    ? $r1 == 0 { @eperr() return }
    @twi_init(72)
    ram ptr u8 $op = $arg
    ram imut $r2: u16 = @_split($r1)
    ram ptr u8 $ap = $r1
    ram imut $addr: u16 = @_hex16($ap)
    @twi_start()
    switch *$op {
        119 -> { # 'w'
            ? $r2 == 0 { @twi_stop() @eperr() return }
            ram ptr u8 $bp = $r2
            @twi_write(($addr & 0x7F) * 2)
            @twi_write(@_hex16($bp) & 0xFF)
            @twi_stop()
            @puts("ok\n")
            return
        }
        114 -> { # 'r'
            @twi_write(($addr & 0x7F) * 2 + 1)
            ram imut $v: u8 = @twi_read_nack()
            @twi_stop()
            @puts("0x")
            @put_hex($v)
            @nl()
            return
        }
        * -> {
            @twi_stop()
            @eperr()
        }
    }
}
