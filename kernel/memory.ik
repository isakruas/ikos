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
# SRAM map. Chosen to fit BOTH atmega32/32a (RAM 0x0060..0x085F) and atmega328p
# (0x0100..0x08FF). Kernel state sits at 0x0340 -- above the compiler statics on
# either part (atmega32 statics start at 0x0060, the 328p at 0x0100; the kernel
# uses ~440 B so 0x0340 leaves a healthy margin) -- and process stacks fill the
# band up to 0x07FF, leaving 0x0800..RAMEND for the scheduler/reset stack on
# whichever device. Only the timer (arch/timer.ik) is truly per-target.
#
#   ..0x033F        compiler statics
#   0x0340..0x0565  kernel state (cleared at boot)
#   0x0566..0x07FF  process stacks (666 B, no overlap with kernel state)
#   0x0800..RAMEND  scheduler / reset stack

# Process table, indexed by pid.
const PROC_STATE: u16 = 0x0340   # u8 [NPROC]
const PROC_SP:    u16 = 0x0344   # u16[NPROC]  saved stack pointer
const PROC_WAKE:  u16 = 0x034C   # u16[NPROC]  wake tick while SLEEPING

# tree(): per-depth "is last child" flags, to draw the right connector column.
const TREE_LAST:  u16 = 0x0352   # u8[14]  -> 0x0352..0x035F

# Scheduler / clock.
const SCHED_SP:   u16 = 0x0360   # u16
const CUR_PROC:   u16 = 0x0362   # u8
const TICKS:      u16 = 0x0364   # u16

# Shell script variables a..z and lazy bus-init flag.
const VARS:       u16 = 0x0368   # u16[26]  -> 0x0368..0x039B
const SPI_READY:  u16 = 0x039C   # u8
const REDIRECT_MODE: u16 = 0x039D # u8 (0=none, 1=overwrite >, 2=append >>)
const CWD_LOC:    u16 = 0x039E   # u16  cwd as a packed (device,node) location

# Shell working memory.
const LINE_BUF:   u16 = 0x03A0   # u8[64]  current input line  -> 0x03A0..0x03DF
const LINE_LEN:   u16 = 0x03E0   # u8
# Redirection target (set by cmd_exec, must persist while the inner command runs
# -- so kept clear of NAME_BUF, which the inner cp/mv use at the same time).
const REDIRECT_DEV:  u16 = 0x03E1 # u8
const REDIRECT_NODE: u16 = 0x03E2 # u16  -> 0x03E2..0x03E3
const EXPAND:     u16 = 0x03E8   # u8[80]  line after $var expansion  -> 0x03E8..0x0437

# Mount table (2 slots).
const MNT_USED:   u16 = 0x0438   # u8 [2]
const MNT_DEV:    u16 = 0x043A   # u8 [2]
const MNT_LOC:    u16 = 0x043C   # u16[2]  -> 0x043C..0x043F

const SCRATCH:    u16 = 0x0440   # u8[80]  script line / file working buffer  -> 0x0440..0x048F
const NAME_BUF:   u16 = 0x0490   # u8[16]  parsed file name / path component  -> 0x0490..0x049F
const REPEAT_RUN: u16 = 0x04A0   # u8[64]  `repeat` loop-body working copy   -> 0x04A0..0x04DF
const BG_FILE:    u16 = 0x04E0   # u16[NPROC] (indexed by pid) -> 6 bytes     -> 0x04E0..0x04E5
const BG_SCRATCH: u16 = 0x04E6   # u8[(NPROC-1) * 64] (indexed by pid-1) -> 128 bytes -> 0x04E6..0x0565

# Cleared to zero at boot.
const BSS_BASE:   u16 = 0x0340
const BSS_LEN:    u16 = 0x0226   # 0x0340..0x0565

# Process stack tops (grow down). pid 0 (shell) gets the most. The three stacks
# tile 0x0566..0x07FF with no gaps and no overlap with the kernel state below.
const STK0_TOP:   u16 = 0x07FF   # 0x06C0..0x07FF (320 B)
const STK1_TOP:   u16 = 0x06BF   # 0x0620..0x06BF (160 B)
const STK2_TOP:   u16 = 0x061F   # 0x0566..0x061F (186 B)

# Process states.
const ST_UNUSED:   u8 = 0
const ST_READY:    u8 = 1
const ST_RUNNING:  u8 = 2
const ST_SLEEPING: u8 = 3
const ST_ZOMBIE:   u8 = 4
