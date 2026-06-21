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
target atmega32

import std/uart
import std/conv
import std/eeprom
import std/spi
import std/twi
import std/adc
import std/wdt
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
    # Disable the watchdog FIRST. The bootloader/fuses can leave it running and
    # the sim doesn't model it, so it only resets in a loop on real silicon.
    # WDE is forced while WDRF is set, so clear the WDT reset flag first
    # (%WDT_STATUS_REG = MCUCSR on classic AVR), then disable via the std helper.
    %WDT_STATUS_REG & 0xF7 -> %WDT_STATUS_REG
    @wdt_disable()
    # (SRAM is already zeroed by the compiler's crt0 before @main, so no
    # explicit .bss clear is needed here.)
    # @bss_clear()
    @uart_init(UART_UBRR)
    @kbanner()
    @sched_init()
    @timer_init()
    ? @fs_blank(DEV_ROOT) == 1 { @fs_format(DEV_ROOT) }
    @_seed_init()
    @proc_start(0, &@shell_main)
    # Arm the watchdog as a hang recovery net (~2 s). It is kicked once per
    # scheduler iteration (@scheduler), so cooperative scheduling keeps it happy;
    # if a process ever locks up without yielding, control never returns to the
    # scheduler, the watchdog is not kicked, and the chip resets itself. Armed
    # only now -- after the slow boot-time init (fs_format) -- so that init can
    # never trip it.
    @wdt_enable(0x07)
    @sei()
    @scheduler()
}
