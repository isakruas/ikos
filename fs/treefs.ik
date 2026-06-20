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
# Hierarchical filesystem. The same tree layout runs on any block device; a
# location is a packed (device, node) pair so paths can cross mount points.
#
#   node i (12 B): [0]=type(0 free,1 file,2 dir) [1]=parent [2..3]=len(u16)
#                  [4..11]=name(8, NUL-padded)
#   data block i:  start_offset + i * block_size
#
# Geometry is dynamic based on device ID:
#   - dev 0, 1 (internal partitions): Fits a 512-byte device (8 nodes, 50 B/file)
#   - dev 2 (external I2C EEPROM): Scaled for larger storage (64 nodes, 256 B/file)

const FS_NODESZ:  u16 = 12
const FS_NAMELEN: u16 = 8
const FS_FREE:    u8 = 0
const FS_FILE:    u8 = 1
const FS_DIR:     u8 = 2

# Returns the maximum number of files/directories allowed on the device.
@fs_nnodes($dev: u8) -> u16 {
    switch $dev {
        2 -> { return 64 } # External EEPROM: 64 nodes
        * -> { return 8 }  # Internal partitions: 8 nodes
    }
}

# Packed location helpers: a u16 = device*256 + node.
@loc($dev: u8, $node: u16) -> u16 { return ($dev * 256) + $node }
@loc_dev($p: u16) -> u8 { return ($p / 256) & 0xFF }
@loc_node($p: u16) -> u16 { return $p & 0xFF }

@_nbase($i: u16) -> u16 { return $i * FS_NODESZ }

@fs_type($dev: u8, $i: u16) -> u8 { return @blk_read($dev, $i * FS_NODESZ) }
@fs_parent($dev: u8, $i: u16) -> u16 { return @blk_read($dev, ($i * FS_NODESZ) + 1) }
@fs_name_byte($dev: u8, $i: u16, $j: u16) -> u8 { return @blk_read($dev, ($i * FS_NODESZ) + 4 + $j) }
# Reads one byte from the file's data block at the given offset.
# Resolves the geometry (start block and block size) dynamically based on dev.
@fs_data_byte($dev: u8, $i: u16, $off: u16) -> u8 {
    ram mut $start: u16 = 96
    ram mut $block: u16 = 50
    switch $dev {
        2 -> {
            768 -> $start
            256 -> $block
        }
    }
    return @blk_read($dev, $start + ($i * $block) + $off)
}

@fs_len($dev: u8, $i: u16) -> u16 {
    ram imut $b: u16 = @_nbase($i)
    ram imut $lo: u8 = @blk_read($dev, $b + 2)
    ram imut $hi: u8 = @blk_read($dev, $b + 3)
    return $lo + ($hi * 256)
}
@_set_len($dev: u8, $i: u16, $n: u16) {
    ram imut $b: u16 = @_nbase($i)
    @blk_write($dev, $b + 2, $n & 0xFF)
    @blk_write($dev, $b + 3, ($n / 256) & 0xFF)
}

@fs_format($dev: u8) {
    ram imut $nnodes: u16 = @fs_nnodes($dev)
    loop 0..$nnodes -> $i {
        @blk_write($dev, @_nbase($i), FS_FREE)
    }
    @blk_write($dev, 1, 0)
    @_set_len($dev, 0, 0)
    @blk_write($dev, 4, 0)
    @blk_write($dev, 0, FS_DIR)
}

@fs_blank($dev: u8) -> u8 {
    ? @fs_ok($dev) == 1 { return 0 }
    return 1
}

# A usable filesystem has a directory at the root node; returns 1 if so.
@fs_ok($dev: u8) -> u8 {
    ? @fs_type($dev, 0) == FS_DIR { return 1 }
    return 0
}

@_alloc($dev: u8) -> u16 {
    ram imut $nnodes: u16 = @fs_nnodes($dev)
    loop 0..$nnodes -> $i {
        ? @fs_type($dev, $i) == FS_FREE { return $i }
    }
    return 0xFFFF
}

# The name to look up is held in NAME_BUF. Comparing against a fixed buffer
# rather than threading a pointer keeps the search's live-register pressure low
# enough that the lookup stays correct two calls deep.
@_nameq($dev: u8, $i: u16) -> u8 {
    ram ptr u8 $name = NAME_BUF
    loop 0..FS_NAMELEN -> $j {
        ram imut $ec: u8 = @fs_name_byte($dev, $i, $j)
        ram imut $rc: u8 = *($name + $j)
        ? $ec != $rc { return 0 }
        ? $ec == 0 { return 1 }
    }
    return 1
}
# Child of $dir named by NAME_BUF, or 0xFFFF.
@fs_child($dev: u8, $dir: u16) -> u16 {
    ram imut $nnodes: u16 = @fs_nnodes($dev)
    loop 0..$nnodes -> $i {
        ? @fs_is_child($dev, $i, $dir) == 1 {
            ? @_nameq($dev, $i) == 1 { return $i }
        }
    }
    return 0xFFFF
}

# Is node $i a used child of $dir? Reads via blk_read directly (keeping the call
# nesting shallow) so it stays correct when called from iterating commands.
@fs_is_child($dev: u8, $i: u16, $dir: u16) -> u8 {
    ? $i == $dir { return 0 }
    ram imut $b: u16 = $i * FS_NODESZ
    ? @blk_read($dev, $b) == FS_FREE { return 0 }
    ? @blk_read($dev, $b + 1) != $dir { return 0 }
    return 1
}

@fs_mknode($dev: u8, $parent: u16, $name: ptr ram u8, $type: u8) -> u16 {
    ram ptr u8 $nb = NAME_BUF
    ram mut $done: u8 = 0
    loop 0..FS_NAMELEN -> $j {
        ram mut $c: u8 = 0
        ? $done == 0 {
            *($name + $j) -> $c
            ? $c == 0 { 1 -> $done }
        }
        $c -> *($nb + $j)
    }
    ? @fs_child($dev, $parent) != 0xFFFF { return 0xFFFF }

    ram imut $n: u16 = @_alloc($dev)
    ? $n == 0xFFFF { return 0xFFFF }
    ram imut $b: u16 = @_nbase($n)
    @blk_write($dev, $b + 1, $parent & 0xFF)
    loop 0..FS_NAMELEN -> $j {
        @blk_write($dev, $b + 4 + $j, *($nb + $j))
    }
    @_set_len($dev, $n, 0)
    @blk_write($dev, $b, $type)
    return $n
}

# Descend one component (held in NAME_BUF) from ($dev, $cur).
@_descend($dev: u8, $cur: u16) -> u16 {
    ? $cur == 0xFFFF { return 0xFFFF }
    ram ptr u8 $name = NAME_BUF
    ? *$name == 46 {
        ? *($name + 1) == 0 { return $cur }
        ? *($name + 1) == 46 {
            ? *($name + 2) == 0 { return @fs_parent($dev, $cur) }
        }
    }
    return @fs_child($dev, $cur)
}

# Descend one path component from a packed location, then cross a mount point if
# the result is one. Returns the new packed location, or 0xFFFF.
@_walk($packed: u16) -> u16 {
    ? $packed == 0xFFFF { return 0xFFFF }
    ram imut $dev: u8 = @loc_dev($packed)
    ram imut $node: u16 = @loc_node($packed)
    ram ptr u8 $name = NAME_BUF
    ram mut $is_dotdot: u8 = 0
    ? *$name == 46 {
        ? *($name + 1) == 46 {
            ? *($name + 2) == 0 {
                1 -> $is_dotdot
            }
        }
    }
    ? $is_dotdot == 1 {
        ? $node == 0 {
            ? $dev != 0 {
                ram imut $mp: u16 = @mount_mp_of($dev)
                ? $mp != 0xFFFF {
                    ram imut $hd: u8 = @loc_dev($mp)
                    ram imut $hn: u16 = @loc_node($mp)
                    return @loc($hd, @fs_parent($hd, $hn))
                }
            }
        }
    }
    ram imut $next: u16 = @_descend($dev, $node)
    ? $next == 0xFFFF { return 0xFFFF }
    ram imut $m: u8 = @mount_at(@loc($dev, $next))
    ? $m != 0xFF { return @loc($m, 0) }
    return @loc($dev, $next)
}

# Resolve a path to a packed (device, node) location, or 0xFFFF. Absolute paths
# start at the root device (loc 0); relative paths at $start. Crosses mounts.
@fs_resolve($path: u16, $start: u16) -> u16 {
    ram ptr u8 $p = $path
    ram mut $cur: u16 = $start
    ram mut $pi: u16 = 0
    ? *$p == 47 {
        0 -> $cur
        1 -> $pi
    }
    ram ptr u8 $nb = NAME_BUF
    ram mut $ci: u16 = 0
    ram mut $done: u8 = 0
    loop 0..63 -> $k {
        ? $done == 0 {
            ram imut $c: u8 = *($p + $pi)
            ram mut $is_sep: u8 = 0
            ? $c == 0 { 1 -> $is_sep }
            ? $c == 47 { 1 -> $is_sep }

            ? $is_sep == 1 {
                0 -> *($nb + $ci)
                ? $ci > 0 { @_walk($cur) -> $cur }
                0 -> $ci
                ? $c == 0 { 1 -> $done }
            } : {
                ? $ci < FS_NAMELEN {
                    $c -> *($nb + $ci)
                    $ci + 1 -> $ci
                }
            }
            $pi + 1 -> $pi
        }
    }
    return $cur
}


# Appends a single byte $c to the end of file $i on device $dev.
@fs_append_byte($dev: u8, $i: u16, $c: u8) {
    ram imut $len: u16 = @fs_len($dev, $i)
    ram mut $block: u16 = 50
    ram mut $start: u16 = 96
    switch $dev {
        2 -> {
            256 -> $block
            768 -> $start
        }
    }
    ? $len < $block {
        @blk_write($dev, $start + ($i * $block) + $len, $c)
        @_set_len($dev, $i, $len + 1)
    }
}

@fs_delete($dev: u8, $i: u16) -> u8 {
    ? @fs_type($dev, $i) == FS_DIR {
        ram imut $nnodes: u16 = @fs_nnodes($dev)
        loop 0..$nnodes -> $k {
            ? @fs_is_child($dev, $k, $i) == 1 { return 0 }
        }
    }
    @blk_write($dev, @_nbase($i), FS_FREE)
    return 1
}
