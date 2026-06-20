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
# Process-facing kernel services. Each yields back to the scheduler by saving
# the caller's stack pointer and switching to the scheduler's.

@getpid() -> u8 {
    ram ptr u8 $c = CUR_PROC
    return *$c
}

@_switch_to_sched($pid: u8) {
    ram imut $slot: u16 = PROC_SP + ($pid * 2)
    ram ptr u16 $sched = SCHED_SP
    @ctx_switch($slot, *$sched)
}

# Give up the CPU; stay runnable.
@sys_yield() {
    ram imut $p: u8 = @getpid()
    ram ptr u8 $st = PROC_STATE
    ST_READY -> *($st + $p)
    @_switch_to_sched($p)
}

# Sleep for $ticks timer ticks.
@sys_sleep($ticks: u16) {
    ram imut $p: u8 = @getpid()
    ram imut $wa: u16 = PROC_WAKE + ($p * 2)
    ram ptr u16 $wake = $wa
    @uptime() + $ticks -> *$wake
    ram ptr u8 $st = PROC_STATE
    ST_SLEEPING -> *($st + $p)
    @_switch_to_sched($p)
}

# Terminate the calling process. Does not return.
@sys_exit() {
    ram imut $p: u8 = @getpid()
    ram ptr u8 $st = PROC_STATE
    ST_UNUSED -> *($st + $p)
    @_switch_to_sched($p)
}
