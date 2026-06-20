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
target atmega328p

import std/uart
import std/conv
import std/eeprom
import std/gpio
import std/spi
import std/twi
import std/adc
import config
import kernel/memory
import arch/cpu
import arch/timer
import drivers/serial
import drivers/bus
import kernel/sched
import kernel/syscall
import fs/block
import fs/mount
import fs/treefs
import shell/script
import shell/commands
import shell/shell

@main {
    @uart_init(UART_UBRR)
    @kbanner()
    @bss_clear()
    @sched_init()
    @timer_init()
    ? @fs_blank(DEV_ROOT) == 1 { @fs_format(DEV_ROOT) }
    @proc_start(0, &@shell_main)
    @sei()
    @scheduler()
}
