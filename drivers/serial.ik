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
# UART console: byte and string output, decimal/hex formatting, line input.
# Wraps std/uart and std/conv.

# Single output chokepoint. When a command's output is redirected to a file
# (REDIRECT_MODE != 0) every byte is appended there instead of the UART, so any
# command's text can be captured without per-command changes. ikOS owns this
# routing here rather than in std/uart so the shared standard library stays generic.
@putc($c: u8) {
    ram ptr u8 $rm = REDIRECT_MODE
    ? *$rm != 0 {
        ram ptr u8 $rd = REDIRECT_DEV
        ram ptr u16 $rn = REDIRECT_NODE
        @fs_append_byte(*$rd, *$rn, $c)
        return
    }
    @uart_send($c)
}

@puts($s: str ram) {
    ram ptr u8 $p = $s
    ram mut $i: u16 = 0
    loop * {
        ram imut $c: u8 = *($p + $i)
        ? $c == 0 { return }
        @putc($c)
        $i + 1 -> $i
    }
}

@nl() { @putc(10) }

@kbanner() {
    @puts("\nikOS v0.1.0-dev1\n(C) 2026 The ikOS Authors  GPL-3.0-or-later\n")
}

# Terse error reply (shared so command text stays out of SRAM).
@eperr() { @putc(63) @putc(10) }

@put_u16($v: u16) {
    ram mut $b: u8[8] = 0
    @utoa($v, &$b[0])
    @puts(&$b[0])
}

@put_hex($v: u16) {
    ram mut $b: u8[8] = 0
    @utoa_hex($v, &$b[0])
    @puts(&$b[0])
}

# Non-blocking input: returns 1 and writes *$dst if a byte is waiting, else 0.
@getc_ready($dst: ptr ram u8) -> u8 {
    ? @uart_available() == 1 {
        @uart_receive() -> *$dst
        return 1
    }
    return 0
}
