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
# CPU primitives: critical sections and context switching.

const %SREG: u16 = 0x005F        # bit 7 (I) = global interrupt enable

# Context switch. @swtch must run with interrupts masked so the SP write is not
# split by an interrupt; they are restored when this context is resumed. A
# freshly bootstrapped process therefore starts with interrupts off and must
# enable them itself (every process entry calls @sei first).
@ctx_switch($old_sp_ptr: u16, $new_sp: u16) {
    @cli()
    @swtch($old_sp_ptr, $new_sp)
    @sei()
}

# Prepare a fresh stack so the first switch into it returns at $entry. A return
# address is a byte address; &@fn is a word address, hence *2. High byte sits at
# the top of the stack. Stores the resulting stack pointer through $sp_slot.
@ctx_bootstrap($stack_top: u16, $sp_slot: u16, $entry: u16) {
    ram imut $eb: u16 = $entry * 2
    ram ptr u8 $s = $stack_top
    ($eb / 256) -> *$s
    ($eb & 0xFF) -> *($s - 1)
    ram ptr u16 $slot = $sp_slot
    $stack_top - 2 -> *$slot
}

# Run $body with interrupts disabled, restoring the prior state. Returns the
# value the SREG I-bit had on entry so the caller can pair enter/leave.
@irq_disable() -> u8 {
    ram imut $s: u8 = %SREG
    @cli()
    ? ($s & 0x80) != 0 { return 1 }
    return 0
}
@irq_restore($were_on: u8) {
    ? $were_on == 1 { @sei() }
}
