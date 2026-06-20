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
# Process table and cooperative scheduler.
#
# Each process owns a stack and runs until it yields (sys_yield/sleep/exit),
# which switches back to the scheduler. The scheduler round-robins READY
# processes, switching into each with a full register+SP context switch, so a
# process keeps its stack and live state across yields.

# Clear the kernel data region; returns 1 only if every byte read back as 0.
@bss_clear() -> u8 {
    ram ptr u8 $p = BSS_BASE
    loop 0..BSS_LEN -> $i { 0 -> *($p + $i) }
    loop 0..BSS_LEN -> $j { ? *($p + $j) != 0 { return 0 } }
    return 1
}

# Mark every slot free; returns 1 only if the table reads back all-UNUSED.
@sched_init() -> u8 {
    ram ptr u8 $st = PROC_STATE
    loop 0..NPROC -> $i { ST_UNUSED -> *($st + $i) }
    loop 0..NPROC -> $j { ? *($st + $j) != ST_UNUSED { return 0 } }
    return 1
}

# Stack top for a pid (pid 0 is the shell and gets the largest stack).
@proc_stack_top($pid: u8) -> u16 {
    switch $pid {
        0 -> { return STK0_TOP }
        1 -> { return STK1_TOP }
        * -> { return STK2_TOP }
    }
}

# Admit a process: bootstrap its stack to begin at $entry and mark it READY.
@proc_start($pid: u8, $entry: u16) {
    ram imut $top: u16  = @proc_stack_top($pid)
    ram imut $slot: u16 = PROC_SP + ($pid * 2)
    @ctx_bootstrap($top, $slot, $entry)
    ram ptr u8 $st = PROC_STATE
    ST_READY -> *($st + $pid)
}

# Lowest free pid, or 0xFF if the table is full.
@proc_alloc() -> u8 {
    ram ptr u8 $st = PROC_STATE
    loop 0..NPROC -> $i {
        ? *($st + $i) == ST_UNUSED { return $i }
    }
    return 0xFF
}

@proc_state($pid: u8) -> u8 {
    ram ptr u8 $st = PROC_STATE
    return *($st + $pid)
}

# Force a process to UNUSED (used by `kill`).
@proc_kill($pid: u8) {
    ram ptr u8 $st = PROC_STATE
    ST_UNUSED -> *($st + $pid)
}

# Never returns. Picks the next READY process and switches into it; control
# comes back here when that process yields.
# u16 array elements are addressed explicitly: pointer arithmetic on a u16
# pointer counts bytes, so PROC_SP[i] lives at PROC_SP + i*2.
@scheduler() {
    ram ptr u8 $st  = PROC_STATE
    ram ptr u8 $cur = CUR_PROC
    loop * {
        ram mut $any_ready: u8 = 0
        loop 0..NPROC -> $i {
            ram ptr u8 $sp_state = $st + $i
            ? *$sp_state == ST_SLEEPING {
                ram imut $wa: u16 = PROC_WAKE + ($i * 2)
                ram ptr u16 $wp = $wa
                ? *$wp <= @uptime() { ST_READY -> *$sp_state }
            }
            ? *$sp_state == ST_READY {
                1 -> $any_ready
                $i -> *$cur
                ST_RUNNING -> *$sp_state
                ram imut $sa: u16 = PROC_SP + ($i * 2)
                ram ptr u16 $sp = $sa
                @ctx_switch(SCHED_SP, *$sp)
            }
        }
        ? $any_ready == 0 {
            @sleep()
        }
    }
}
