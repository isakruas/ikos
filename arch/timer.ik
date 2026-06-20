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
# Timer0 heartbeat: a periodic compare-match interrupt driving uptime and sleep.
# CTC, prescaler 1024, TOP = 255 -> a tick every 256*1024/16e6 = 16.4 ms.
#
# This is the per-target HAL: each supported device supplies its own ISR vector
# and `@timer_init` (its Timer0 registers differ). Registers are written through
# u8 pointers (8-bit stores) because a 16-bit store to a register would also
# write the next byte -- e.g. on atmega32 OCR0 (0x5C) is next to SPL (0x5D).

@uptime() -> u16 {
    ram ptr u16 $t = TICKS
    return *$t
}

? target == atmega32 {
    isr TIMER0_COMP {
        ram ptr u16 $t = TICKS
        *$t + 1 -> *$t
    }
    @timer_init() {
        ram ptr u8 $ocr = 0x005C
        255 -> *$ocr            # OCR0
        ram ptr u8 $timsk = 0x0059
        0x02 -> *$timsk         # TIMSK: OCIE0
        ram ptr u8 $tccr = 0x0053
        0x0D -> *$tccr          # TCCR0: WGM01 (CTC) | CS02|CS00 (prescaler 1024)
    }
}

? target == atmega328p {
    isr TIMER0_COMPA {
        ram ptr u16 $t = TICKS
        *$t + 1 -> *$t
    }
    @timer_init() {
        ram ptr u8 $ocr = 0x0047
        255 -> *$ocr            # OCR0A
        ram ptr u8 $tccra = 0x0044
        0x02 -> *$tccra         # TCCR0A: WGM01 (CTC)
        ram ptr u8 $timsk = 0x006E
        0x02 -> *$timsk         # TIMSK0: OCIE0A
        ram ptr u8 $tccrb = 0x0045
        0x05 -> *$tccrb         # TCCR0B: CS02|CS00 (prescaler 1024)
    }
}
