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
# Interactive shell: process 0. Reads a line from the UART, runs it, repeats.
# Non-blocking: yields the CPU while waiting for input so other processes run.

@_prompt() {
    ? @_cwd() == 0 { @putc(47) } : { @_pwd(@_cwd()) }
    @puts("$ ")
}

# Finish the current line: run it (only if non-empty) and show a fresh prompt.
# An empty line just reprompts, so CR, LF and CRLF all submit cleanly without
# running an empty command (which would print '?').
# Finish the current line: run it (only if non-empty) and show a fresh prompt.
# An empty line just reprompts, so CR, LF and CRLF all submit cleanly without
# running an empty command (which would print '?').
@_submit() {
    ram ptr u8 $len = LINE_LEN
    @nl()
    ? *$len > 0 {
        ram ptr u8 $buf = LINE_BUF
        0 -> *($buf + *$len)
        @cmd_exec(LINE_BUF)
        0 -> *$len
    }
    @_prompt()
}

@_key($c: u8) {
    ram ptr u8 $len = LINE_LEN
    # Submit the line on carriage return (13) OR line feed (10).
    ? $c == 13 {
        @_submit()
        return
    }
    ? $c == 10 {
        @_submit()
        return
    }
    # Backspace / delete.
    ? $c == 8 {
        ? *$len > 0 {
            *$len - 1 -> *$len
            @putc(8)
            @putc(32)
            @putc(8)
        }
        return
    }
    ? $c < 32 { return }
    ? *$len >= 62 { return }
    ram ptr u8 $buf = LINE_BUF
    $c -> *($buf + *$len)
    *$len + 1 -> *$len
    @putc($c)
}

@shell_main() {
    @sei()
    ram ptr u8 $len = LINE_LEN
    0 -> *$len
    @puts("\nikOS. type 'help'.\n")
    @_prompt()
    loop * {
        ram mut $c: u8 = 0
        ? @getc_ready(&$c) == 1 {
            @_key($c)
        } : {
            @sys_yield()
        }
    }
}
