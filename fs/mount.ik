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
# Mount table: maps a directory (a packed device,node location) to the device
# whose root replaces it during path resolution.

const MAX_MNT: u16 = 2

@mount_add($mp: u16, $dev: u8) -> u8 {
    loop 0..MAX_MNT -> $k {
        ram ptr u8 $used = MNT_USED + $k
        ? *$used == 0 {
            1 -> *$used
            ram ptr u8 $md = MNT_DEV + $k
            $dev -> *$md
            ram ptr u16 $lp = MNT_LOC + ($k * 2)
            $mp -> *$lp
            return 1
        }
    }
    return 0
}

# Device mounted at location $mp, or 0xFF.
@mount_at($mp: u16) -> u8 {
    loop 0..MAX_MNT -> $k {
        ram ptr u8 $used = MNT_USED + $k
        ? *$used == 1 {
            ram ptr u16 $lp = MNT_LOC + ($k * 2)
            ? *$lp == $mp {
                ram ptr u8 $md = MNT_DEV + $k
                return *$md
            }
        }
    }
    return 0xFF
}

# Mountpoint location of a mounted device, or 0xFFFF.
@mount_mp_of($dev: u8) -> u16 {
    loop 0..MAX_MNT -> $k {
        ram ptr u8 $used = MNT_USED + $k
        ? *$used == 1 {
            ram ptr u8 $md = MNT_DEV + $k
            ? *$md == $dev {
                ram ptr u16 $lp = MNT_LOC + ($k * 2)
                return *$lp
            }
        }
    }
    return 0xFFFF
}

# Remove the mount whose mounted device is $dev. Returns 1 if removed.
@mount_remove_dev($dev: u8) -> u8 {
    loop 0..MAX_MNT -> $k {
        ram ptr u8 $used = MNT_USED + $k
        ? *$used == 1 {
            ram ptr u8 $md = MNT_DEV + $k
            ? *$md == $dev {
                0 -> *$used
                return 1
            }
        }
    }
    return 0
}
