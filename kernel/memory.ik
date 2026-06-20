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
# SRAM map. Chosen to fit BOTH atmega32 (RAM 0x0060..0x085F) and atmega328p
# (0x0100..0x08FF): kernel data sits at 0x0400 (above the compiler statics on
# either part) and process stacks stay below 0x0700, so the scheduler's reset
# stack uses whatever the device's RAMEND is. Only the timer (arch/timer.ik) is
# truly per-target.
#
#   ..0x03FF        compiler statics
#   0x0400..0x05E3  kernel state (cleared at boot)
#   0x05E4..0x07FF  process stacks
#   0x0800..RAMEND  scheduler / reset stack

# Process table, indexed by pid.
const PROC_STATE: u16 = 0x0400   # u8 [NPROC]
const PROC_SP:    u16 = 0x0404   # u16[NPROC]  saved stack pointer
const PROC_WAKE:  u16 = 0x040C   # u16[NPROC]  wake tick while SLEEPING

# tree(): per-depth "is last child" flags, to draw the right connector column.
const TREE_LAST:  u16 = 0x0412   # u8[14]

# Scheduler / clock.
const SCHED_SP:   u16 = 0x0420   # u16
const CUR_PROC:   u16 = 0x0422   # u8
const TICKS:      u16 = 0x0424   # u16

# Shell script variables a..z and lazy bus-init flag.
const VARS:       u16 = 0x0428   # u16[26]  -> 0x0428..0x045B
const SPI_READY:  u16 = 0x045C   # u8
const REDIRECT_MODE: u16 = 0x045D # u8 (0=none, 1=overwrite >, 2=append >>)
const CWD_LOC:    u16 = 0x045E   # u16  cwd as a packed (device,node) location

# Shell working memory.
const LINE_BUF:   u16 = 0x0460   # u8[64]  current input line
const LINE_LEN:   u16 = 0x04A0   # u8
const EXPAND:     u16 = 0x04A8   # u8[80]  line after $var expansion

# Mount table (2 slots).
const MNT_USED:   u16 = 0x04F8   # u8 [2]
const MNT_DEV:    u16 = 0x04FA   # u8 [2]
const MNT_LOC:    u16 = 0x04FC   # u16[2]

const SCRATCH:    u16 = 0x0500   # u8[80]  script line / file working buffer
const NAME_BUF:   u16 = 0x0550   # u8[16]  parsed file name / path component
const REDIRECT_DEV:  u16 = 0x055A # u8
const REDIRECT_NODE: u16 = 0x055B # u16
const REPEAT_RUN: u16 = 0x0560   # u8[64]  `repeat` loop-body working copy
const BG_FILE:    u16 = 0x05A0   # u16[NPROC] (indexed by pid) -> 6 bytes
const BG_SCRATCH: u16 = 0x05A6   # u8[(NPROC-1) * 64] (indexed by pid-1) -> 128 bytes

# Cleared to zero at boot.
const BSS_BASE:   u16 = 0x0400
const BSS_LEN:    u16 = 0x0226   # 0x0400..0x0625

# Process stack tops (grow down). pid 0 (shell) gets the most.
const STK0_TOP:   u16 = 0x07FF   # 0x06E0..0x07FF (288 B)
const STK1_TOP:   u16 = 0x06DF   # 0x0660..0x06DF (128 B)
const STK2_TOP:   u16 = 0x065F   # 0x05E4..0x065F (124 B)

# Process states.
const ST_UNUSED:   u8 = 0
const ST_READY:    u8 = 1
const ST_RUNNING:  u8 = 2
const ST_SLEEPING: u8 = 3
const ST_ZOMBIE:   u8 = 4
