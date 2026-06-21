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
# Block-storage layer. A filesystem addresses bytes within a device; the device
# id selects the backend:
#   0  on-chip EEPROM (the root filesystem, uses the whole 1 KB)
#   2  external I2C EEPROM (24Cxx) at 0x50  (validated on real hardware)

const DEV_ROOT: u8  = 0
const DEV_I2C:  u8  = 2
const PART_SIZE: u16 = 0x400
const I2C_ADDR:  u8  = 0x50

@_i2c_start_addr($addr: u16) {
    @twi_init(72)
    @twi_start()
    @twi_write(I2C_ADDR * 2)
    @twi_write(($addr / 256) & 0xFF)
    @twi_write($addr & 0xFF)
}
@_i2c_read($addr: u16) -> u8 {
    @_i2c_start_addr($addr)
    @twi_start()
    @twi_write(I2C_ADDR * 2 + 1)
    ram imut $v: u8 = @twi_read_nack()
    @twi_stop()
    return $v
}
@_i2c_write($addr: u16, $val: u8) {
    @_i2c_start_addr($addr)
    @twi_write($val)
    @twi_stop()
}

@blk_read($dev: u8, $addr: u16) -> u8 {
    switch $dev {
        DEV_I2C -> { return @_i2c_read($addr) }
        * -> {
            ram imut $base: u16 = $dev
            return @eeprom_read(($base * PART_SIZE) + $addr)
        }
    }
}
@blk_write($dev: u8, $addr: u16, $val: u8) {
    switch $dev {
        DEV_I2C -> { @_i2c_write($addr, $val) }
        * -> {
            ram imut $base: u16 = $dev
            @eeprom_write(($base * PART_SIZE) + $addr, $val)
        }
    }
}
