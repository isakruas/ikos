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
# Command interpreter: parse one line and run it. Also runs script files.

@_streq($a: ptr ram u8, $b: str ram) -> u8 {
    ram mut $i: u16 = 0
    loop * {
        ram imut $ca: u8 = *($a + $i)
        ram imut $cb: u8 = *($b + $i)
        ? $ca != $cb { return 0 }
        ? $ca == 0 { return 1 }
        $i + 1 -> $i
    }
    return 0
}

@_split($line: u16) -> u16 {
    ram ptr u8 $p = $line
    loop 0..63 -> $i {
        ram imut $c: u8 = *($p + $i)
        ? $c == 0 { return 0 }
        ? $c == 32 {
            0 -> *($p + $i)
            return $line + $i + 1
        }
    }
    return 0
}

@_hex16($p: ptr ram u8) -> u16 {
    ram mut $v: u16 = 0
    ram mut $i: u16 = 0
    ? *$p == 48 {
        ? *($p + 1) == 120 { 2 -> $i }
    }
    loop * {
        ram imut $c: u8 = *($p + $i)
        ram mut $d: u8 = 16
        ? $c >= 48 { ? $c <= 57 { $c - 48 -> $d } }
        ram imut $cl: u8 = $c | 32
        ? $cl >= 97 { ? $cl <= 102 { $cl - 87 -> $d } }
        ? $d == 16 { return $v }
        $v * 16 + $d -> $v
        $i + 1 -> $i
    }
    return $v
}

@_copy($src: u16, $dst: u16) {
    ram ptr u8 $s = $src
    ram ptr u8 $d = $dst
    loop 0..63 -> $i {
        ram imut $c: u8 = *($s + $i)
        $c -> *($d + $i)
        ? $c == 0 { return }
    }
    0 -> *($d + 63)
}

@_cwd() -> u16 {
    ram ptr u16 $cw = CWD_LOC
    return *$cw
}

# Append a NUL-terminated string to file $node on the root device, byte by byte.
@_append_str($node: u16, $s: str ram) {
    ram ptr u8 $p = $s
    ram mut $i: u16 = 0
    loop * {
        ram imut $c: u8 = *($p + $i)
        ? $c == 0 { return }
        @fs_append_byte(DEV_ROOT, $node, $c)
        $i + 1 -> $i
    }
}

# Create the /init boot script with a default line if it is missing. The shell
# runs /init at every start, so editing it on the EEPROM customises the startup
# output and can run any commands. Each line is run through the script runner.
@_seed_init() {
    ? @fs_resolve("init", 0) != 0xFFFF { return }
    ram imut $n: u16 = @fs_mknode(DEV_ROOT, 0, "init", FS_FILE)
    ? $n == 0xFFFF { return }
    #@_append_str($n, "say ls cd pwd cat mkd new rm cp mv run fmt mnt umnt\n")
    #@_append_str($n, "say ps say peek poke kill spi i2c adc set if rep up cls\n")
}

@cmd_ps() {
    ram ptr u8 $st = PROC_STATE
    loop 0..NPROC -> $i {
        ram imut $s: u8 = *($st + $i)
        ? $s != ST_UNUSED {
            @putc($i + 48)
            @putc(32)
            ram mut $c: u8 = 63
            ? $s == ST_READY { 82 -> $c }
            ? $s == ST_RUNNING { 88 -> $c }
            ? $s == ST_SLEEPING { 83 -> $c }
            @putc($c)
            @nl()
        }
    }
}

@cmd_uptime() {
    @puts("T: ")
    @put_u16(@uptime())
    @nl()
}

@cmd_clear() { @puts("\x1b[2J\x1b[H") }

@cmd_say($arg: u16) {
    ? $arg != 0 {
        ram ptr u8 $a = $arg
        @puts($a)
    }
    @nl()
}

# --- filesystem ---
@_pname($dev: u8, $n: u16) {
    loop 0..FS_NAMELEN -> $j {
        ram imut $c: u8 = @fs_name_byte($dev, $n, $j)
        ? $c != 0 { @putc($c) }
    }
}

@_pwd($loc: u16) {
    ram imut $dev: u8 = @loc_dev($loc)
    ram imut $node: u16 = @loc_node($loc)
    ? $node == 0 {
        ? $dev == 0 { return }
        ram imut $mp: u16 = @mount_mp_of($dev)
        ? $mp != 0xFFFF { @_pwd($mp) }
        return
    }
    @_pwd(@loc($dev, @fs_parent($dev, $node)))
    @putc(47)
    @_pname($dev, $node)
}
@cmd_pwd() {
    ? @_cwd() == 0 { @putc(47) } : { @_pwd(@_cwd()) }
    @nl()
}

@cmd_cd($arg: u16) {
    ram ptr u16 $cw = CWD_LOC
    ? $arg == 0 {
        0 -> *$cw
        return
    }
    ram imut $loc: u16 = @fs_resolve($arg, @_cwd())
    ? $loc == 0xFFFF { @eperr() return }
    ? @fs_type(@loc_dev($loc), @loc_node($loc)) != FS_DIR { @eperr() return }
    $loc -> *$cw
}

@_resolve_parent($path: u16, $parent_loc_out: ptr ram u16) -> u16 {
    ram ptr u8 $p = $path
    ram mut $last_slash: u16 = 0xFFFF
    ram mut $i: u16 = 0
    loop 0..64 -> $j {
        ram imut $c: u8 = *($p + $i)
        ? $c == 0 { 64 -> $j } : {
            ? $c == 47 { $i -> $last_slash }
            $i + 1 -> $i
        }
    }
    ram imut $cwd_loc: u16 = @_cwd()
    ram mut $parent_loc: u16 = $cwd_loc
    ram mut $fn_offset: u16 = 0
    ? $last_slash != 0xFFFF {
        ram ptr u8 $slash_ptr = $p + $last_slash
        0 -> *$slash_ptr
        ? $last_slash == 0 {
            0 -> $parent_loc
        } : {
            @fs_resolve($path, $cwd_loc) -> $parent_loc
        }
        47 -> *$slash_ptr
        $last_slash + 1 -> $fn_offset
    }
    $parent_loc -> *$parent_loc_out
    return $path + $fn_offset
}

@_mkdir_new($arg: u16, $type: u8) {
    ? $arg == 0 { @eperr() return }
    ram mut $parent_loc: u16 = 0
    ram imut $fn: u16 = @_resolve_parent($arg, &$parent_loc)
    ? $parent_loc == 0xFFFF { @eperr() return }
    ? @fs_mknode(@loc_dev($parent_loc), @loc_node($parent_loc), $fn, $type) == 0xFFFF { @eperr() }
}
@cmd_mkdir($arg: u16) { @_mkdir_new($arg, FS_DIR) }
@cmd_new($arg: u16) { @_mkdir_new($arg, FS_FILE) }

@cmd_cat($arg: u16) {
    ? $arg == 0 { @eperr() return }
    ram imut $loc: u16 = @fs_resolve($arg, @_cwd())
    ? $loc == 0xFFFF { @eperr() return }
    ram imut $dev: u8 = @loc_dev($loc)
    ram imut $n: u16 = @loc_node($loc)
    ? @fs_type($dev, $n) != FS_FILE { @eperr() return }
    ram imut $len: u16 = @fs_len($dev, $n)
    loop 0..$len -> $k { @putc(@fs_data_byte($dev, $n, $k)) }
    @nl()
}

# Delete $node and its whole subtree (depth-first): children first, so each dir
# is empty by the time @fs_delete reaches it. fs_delete only marks nodes FS_FREE
# (no index shifting), so the scan stays valid while we recurse.
@_rm_tree($dev: u8, $node: u16, $depth: u16) {
    # Bound recursion to the same 14-level limit @_tree uses, so a deep tree
    # cannot overflow the small (288 B) shell stack -- especially since the
    # timer ISR may nest its frame on top mid-recursion.
    ? $depth < 14 {
        ram imut $nnodes: u16 = @fs_nnodes($dev)
        loop 0..$nnodes -> $i {
            ? @fs_is_child($dev, $i, $node) == 1 { @_rm_tree($dev, $i, $depth + 1) }
        }
    }
    @fs_delete($dev, $node)
}

@cmd_rm($arg: u16) {
    ? $arg == 0 { @eperr() return }
    ram ptr u8 $a = $arg
    ram mut $len: u16 = 0
    loop 0..64 -> $k {
        ? *($a + $k) == 0 { 64 -> $k } : { $k + 1 -> $len }
    }
    # "dir/*", "/*" or "*": drop the trailing '*' and wipe the directory's
    # whole contents recursively, leaving the directory itself in place.
    ? $len > 0 {
        ? *($a + ($len - 1)) == 42 {
            0 -> *($a + ($len - 1))
            ram imut $d: u16 = @fs_resolve($arg, @_cwd())
            ? $d == 0xFFFF { @eperr() return }
            ram imut $dv: u8 = @loc_dev($d)
            ram imut $dn: u16 = @loc_node($d)
            loop 0..@fs_nnodes($dv) -> $i {
                ? @fs_is_child($dv, $i, $dn) == 1 { @_rm_tree($dv, $i, 1) }
            }
            return
        }
    }
    ram imut $loc: u16 = @fs_resolve($arg, @_cwd())
    ? $loc == 0xFFFF { @eperr() return }
    ? @loc_node($loc) == 0 { @eperr() return }
    @_rm_tree(@loc_dev($loc), @loc_node($loc), 0)
}

# Copy file ($sd:$sn) into directory ($dd:$dn), keeping its name. Crosses devices
# (so it works between the internal EEPROM and a mounted external volume). Returns
# the new node, or 0xFFFF on failure.
@_fs_copy($sd: u8, $sn: u16, $dd: u8, $dn: u16) -> u16 {
    ram ptr u8 $nm = NAME_BUF
    loop 0..FS_NAMELEN -> $j {
        ram imut $c: u8 = @fs_name_byte($sd, $sn, $j)
        $c -> *($nm + $j)
    }
    0 -> *($nm + FS_NAMELEN)
    ram imut $new: u16 = @fs_mknode($dd, $dn, $nm, FS_FILE)
    ? $new == 0xFFFF { return 0xFFFF }
    ram imut $len: u16 = @fs_len($sd, $sn)
    loop 0..$len -> $k {
        ram imut $b: u8 = @fs_data_byte($sd, $sn, $k)
        @fs_append_byte($dd, $new, $b)
    }
    return $new
}

# cp <file> <dir>   copy a file into a directory (same or another device).
@cmd_cp($arg: u16) {
    ? $arg == 0 { @eperr() return }
    ram imut $dst: u16 = @_split($arg)
    ? $dst == 0 { @eperr() return }
    ram imut $sloc: u16 = @fs_resolve($arg, @_cwd())
    ? $sloc == 0xFFFF { @eperr() return }
    ram imut $dloc: u16 = @fs_resolve($dst, @_cwd())
    ? $dloc == 0xFFFF { @eperr() return }
    ram imut $sd: u8  = @loc_dev($sloc)
    ram imut $sn: u16 = @loc_node($sloc)
    ram imut $dd: u8  = @loc_dev($dloc)
    ram imut $dn: u16 = @loc_node($dloc)
    ? @fs_type($sd, $sn) != FS_FILE { @eperr() return }
    ? @fs_type($dd, $dn) != FS_DIR { @eperr() return }
    ? @_fs_copy($sd, $sn, $dd, $dn) == 0xFFFF { @eperr() }
}

# mv <node> <dir>   move into a directory. Same device = re-parent (no copy);
# across devices a file is copied then the source removed.
@cmd_mv($arg: u16) {
    ? $arg == 0 { @eperr() return }
    ram imut $dst: u16 = @_split($arg)
    ? $dst == 0 { @eperr() return }
    ram imut $sloc: u16 = @fs_resolve($arg, @_cwd())
    ? $sloc == 0xFFFF { @eperr() return }
    ? @loc_node($sloc) == 0 { @eperr() return }
    ram imut $dloc: u16 = @fs_resolve($dst, @_cwd())
    ? $dloc == 0xFFFF { @eperr() return }
    ? $dloc == $sloc { @eperr() return }
    ram imut $sd: u8  = @loc_dev($sloc)
    ram imut $sn: u16 = @loc_node($sloc)
    ram imut $dd: u8  = @loc_dev($dloc)
    ram imut $dn: u16 = @loc_node($dloc)
    ? @fs_type($dd, $dn) != FS_DIR { @eperr() return }
    ? $sd == $dd {
        ram mut $temp: u16 = $dn
        loop 0..8 -> $step {
            ? $temp == $sn { @eperr() return }
            @fs_parent($sd, $temp) -> $temp
        }
        @blk_write($sd, @_nbase($sn) + 1, $dn)
    } : {
        ? @fs_type($sd, $sn) != FS_FILE { @eperr() return }
        ? @_fs_copy($sd, $sn, $dd, $dn) == 0xFFFF { @eperr() return }
        @fs_delete($sd, $sn)
    }
}

# Print one node and its subtree. The prefix columns are drawn from the per-depth
# "last child" flags: an ancestor that was a last child gets blank space, others
# get a continuing vertical bar.
@_tree($dev: u8, $n: u16, $depth: u16, $is_last: u8) {
    ? $depth > 0 {
        ram ptr u8 $tl = TREE_LAST
        loop 1..$depth -> $a {
            ? *($tl + $a) == 1 { @puts("    ") } : { @puts("|   ") }
        }
        ? $is_last == 1 { @puts("`-- ") } : { @puts("|-- ") }
        $is_last -> *($tl + $depth)
    }
    @_pname($dev, $n)
    ? @fs_type($dev, $n) == FS_DIR { @putc(47) }
    @nl()
    ? $depth < 13 {
        ram imut $m: u8 = @mount_at(@loc($dev, $n))
        ? $m != 0xFF {
            @_tree_kids($m, 0, $depth + 1)
        } : {
            ? @fs_type($dev, $n) == FS_DIR {
                @_tree_kids($dev, $n, $depth + 1)
            }
        }
    }
}
# Recurse over a directory's children, tagging the highest-indexed one as last.
@_tree_kids($dev: u8, $parent: u16, $depth: u16) {
    ram mut $last: u16 = 0
    ram mut $any: u8 = 0
    ram imut $nnodes: u16 = @fs_nnodes($dev)
    loop 0..$nnodes -> $i {
        ? @fs_is_child($dev, $i, $parent) == 1 {
            $i -> $last
            1 -> $any
        }
    }
    ? $any == 0 { return }
    loop 0..$nnodes -> $j {
        ? @fs_is_child($dev, $j, $parent) == 1 {
            ram mut $il: u8 = 0
            ? $j == $last { 1 -> $il }
            @_tree($dev, $j, $depth, $il)
        }
    }
}
# ls [path]   list a directory and everything under it.
@cmd_ls($arg: u16) {
    ram mut $loc: u16 = @_cwd()
    ? $arg != 0 {
        @fs_resolve($arg, @_cwd()) -> $loc
        ? $loc == 0xFFFF { @eperr() return }
    }
    @_tree(@loc_dev($loc), @loc_node($loc), 0, 1)
}

# fmt [dev]   wipe a filesystem and re-create an empty root. No argument formats
# the internal EEPROM (DEV_ROOT); `fmt 1`/`fmt 2` format another on-chip or the
# external I2C volume. Use it to clear stale data from the (non-volatile) storage.
@cmd_fmt($arg: u16) {
    ram mut $dev: u8 = DEV_ROOT
    ? $arg != 0 { @atoi($arg) & 0xFF -> $dev }
    @fs_format($dev)
    ? $dev == DEV_ROOT {
        ram ptr u16 $cw = CWD_LOC
        0 -> *$cw
        @_seed_init()
    }
}

# mnt <dev> <path>   redirect directory <path> to device <dev> (formats if blank)
@cmd_mount($arg: u16) {
    ? $arg == 0 { @eperr() return }
    ram imut $pa: u16 = @_split($arg)
    ? $pa == 0 { @eperr() return }
    ram ptr u8 $dp = $arg
    ram imut $dev: u8 = @atoi($dp) & 0xFF
    ram imut $loc: u16 = @fs_resolve($pa, @_cwd())
    ? $loc == 0xFFFF { @eperr() return }
    ? @fs_type(@loc_dev($loc), @loc_node($loc)) != FS_DIR { @eperr() return }
    ? @fs_blank($dev) == 1 { @fs_format($dev) }
    ? @mount_add($loc, $dev) == 0 { @eperr() }
}
@cmd_umount($arg: u16) {
    ? $arg == 0 { @eperr() return }
    ram imut $loc: u16 = @fs_resolve($arg, @_cwd())
    ? $loc == 0xFFFF { @eperr() return }
    ? @mount_remove_dev(@loc_dev($loc)) == 0 { @eperr() }
}

# Run a file as a script: one command per line.
@cmd_run($arg: u16) {
    ? $arg == 0 { @eperr() return }
    # a trailing " &" runs the script as a background process
    ram imut $rest: u16 = @_split($arg)
    ram mut $bg: u8 = 0
    ? $rest != 0 {
        ram ptr u8 $r = $rest
        ? *$r == 38 { 1 -> $bg }
    }
    ram imut $loc: u16 = @fs_resolve($arg, @_cwd())
    ? $loc == 0xFFFF { @eperr() return }
    ram imut $dev: u8 = @loc_dev($loc)
    ram imut $node: u16 = @loc_node($loc)
    ? @fs_type($dev, $node) != FS_FILE { @eperr() return }
    ? $bg == 1 {
        ram imut $pid: u8 = @proc_alloc()
        ? $pid == 0xFF { @eperr() return }
        ram imut $ba: u16 = BG_FILE + ($pid * 2)
        ram ptr u16 $bf = $ba
        $loc -> *$bf
        @proc_start($pid, &@bg_run)
        return
    }
    ram imut $len: u16 = @fs_len($dev, $node)
    ram ptr u8 $sb = SCRATCH
    ram mut $j: u16 = 0
    loop 0..$len -> $k {
        ram imut $c: u8 = @fs_data_byte($dev, $node, $k)
        ? $c == 10 {
            0 -> *($sb + $j)
            @cmd_exec(SCRATCH)
            0 -> $j
        } : {
            ? $j < 78 {
                $c -> *($sb + $j)
                $j + 1 -> $j
            }
        }
    }
    ? $j > 0 {
        0 -> *($sb + $j)
        @cmd_exec(SCRATCH)
    }
}

# --- memory / IO ---
@cmd_peek($arg: u16) {
    ? $arg == 0 { @eperr() return }
    ram imut $addr: u16 = @_hex16($arg)
    ram ptr u8 $m = $addr
    @put_hex(*$m)
    @nl()
}
@cmd_poke($arg: u16) {
    ram imut $varg: u16 = @_split($arg)
    ? $varg == 0 { @eperr() return }
    ram imut $addr: u16 = @_hex16($arg)
    ram imut $val: u16 = @_hex16($varg)
    ram ptr u8 $m = $addr
    ($val & 0xFF) -> *$m
}

# sbi/cbi <addr> <bit>   set or clear a single bit of the byte at <addr> via
# read-modify-write, so the other 7 bits are preserved (e.g. drive one GPIO pin
# without disturbing the rest of the port). <addr> is hex, <bit> is 0..7.
@_setclr($arg: u16, $set: u8) {
    ram imut $barg: u16 = @_split($arg)
    ? $barg == 0 { @eperr() return }
    ram imut $addr: u16 = @_hex16($arg)
    ram imut $bit: u16 = @_hex16($barg)
    ram mut $mask: u8 = 1
    loop 0..$bit -> $i { $mask * 2 -> $mask }
    ram ptr u8 $m = $addr
    ? $set == 1 { *$m | $mask -> *$m } : { *$m & ~$mask -> *$m }
}
@cmd_sbi($arg: u16) { @_setclr($arg, 1) }
@cmd_cbi($arg: u16) { @_setclr($arg, 0) }

# slp <ticks>   sleep this (shell) process for <ticks> timer ticks, yielding the
# CPU to other processes meanwhile.
@cmd_slp($arg: u16) {
    ? $arg == 0 { @eperr() return }
    @sys_sleep(@atoi($arg))
}
@cmd_kill($arg: u16) {
    ? $arg == 0 { @eperr() return }
    ram imut $pid: u16 = @atoi($arg)
    ? ($pid - 1) >= 2 { @eperr() return }
    @proc_kill($pid & 0xFF)
}

# Background job: run the script at BG_FILE + pid*2 line by line, yielding between
# commands so the shell stays responsive.
@bg_run() {
    @sei()
    ram imut $pid: u8 = @getpid()
    ram ptr u16 $bf = BG_FILE + ($pid * 2)
    ram imut $loc: u16 = *$bf
    ram imut $dev: u8 = @loc_dev($loc)
    ram imut $node: u16 = @loc_node($loc)
    ram imut $len: u16 = @fs_len($dev, $node)
    ram imut $sba: u16 = BG_SCRATCH + (($pid - 1) * 64)
    ram ptr u8 $sb = $sba
    ram mut $k: u16 = 0
    ram mut $j: u16 = 0
    loop * {
        ? $k >= $len {
            ? $j > 0 {
                0 -> *($sb + $j)
                @cmd_exec($sb)
            }
            @sys_exit()
        }
        ram imut $pid2: u8 = @getpid()
        ram ptr u16 $bf2 = BG_FILE + ($pid2 * 2)
        ram imut $loc2: u16 = *$bf2
        ram imut $c: u8 = @fs_data_byte(@loc_dev($loc2), @loc_node($loc2), $k)
        ? $c == 10 {
            0 -> *($sb + $j)
            @cmd_exec($sb)
            0 -> $j
            @sys_yield()
        } : {
            ? $j < 62 {
                $c -> *($sb + $j)
                $j + 1 -> $j
            }
        }
        $k + 1 -> $k
    }
}

# Parse and dispatch one command.
@cmd_exec($line: u16) {
    ram ptr u8 $p = $line
    ram mut $redir_idx: u16 = 0xFFFF
    ram mut $redir_mode: u8 = 0
    loop 0..64 -> $i {
        ram imut $c: u8 = *($p + $i)
        ? $c == 62 { # '>'
            ? $redir_mode == 0 {
                ram imut $next: u8 = *($p + $i + 1)
                ? $next == 62 { 2 -> $redir_mode } : { 1 -> $redir_mode }
                $i -> $redir_idx
                64 -> $i
            }
        }
        ? $c == 0 { 64 -> $i }
    }

    ? $redir_mode > 0 {
        ram mut $fn: u16 = $redir_idx + 1
        ? $redir_mode == 2 { $fn + 1 -> $fn }
        # Skip leading spaces of filename
        loop 0..64 -> $j {
            ram imut $fc: u8 = *($p + $fn)
            ? $fc != 32 { 64 -> $j } : { $fn + 1 -> $fn }
        }
        # Terminate filename at first trailing space or NUL
        ram mut $fe: u16 = $fn
        loop 0..64 -> $j {
            ram imut $fc: u8 = *($p + $fe)
            ? $fc == 0 { 64 -> $j }
            ? $fc == 32 {
                0 -> *($p + $fe)
                64 -> $j
            }
            $fe + 1 -> $fe
        }
        # Truncate command part before redirection (and trailing spaces)
        0 -> *($p + $redir_idx)
        loop 0..64 -> $j {
            ? $redir_idx == 0 { 64 -> $j } : {
                $redir_idx - 1 -> $redir_idx
                ? *($p + $redir_idx) == 32 {
                    0 -> *($p + $redir_idx)
                } : {
                    64 -> $j
                }
            }
        }

        # Resolve or create the file
        ram mut $parent_loc: u16 = 0
        ram imut $fn_ptr: u16 = @_resolve_parent($p + $fn, &$parent_loc)
        ? $parent_loc == 0xFFFF { @eperr() return }
        ram mut $loc: u16 = @fs_resolve($p + $fn, @_cwd())
        ? $loc == 0xFFFF {
            # fs_mknode returns a bare node index; pack it with the parent's
            # device so a redirect onto a mounted volume writes to that device
            # (not always dev 0).
            ram imut $nn: u16 = @fs_mknode(@loc_dev($parent_loc), @loc_node($parent_loc), $fn_ptr, FS_FILE)
            ? $nn != 0xFFFF { @loc(@loc_dev($parent_loc), $nn) -> $loc }
        }
        ? $loc == 0xFFFF { @eperr() return }

        # For '>' overwrite redirection, truncate file to 0 length
        ? $redir_mode == 1 {
            @fs_truncate(@loc_dev($loc), @loc_node($loc))
        }

        # Set redirection globals
        ram ptr u8 $rm = REDIRECT_MODE
        ram ptr u8 $rd = REDIRECT_DEV
        ram ptr u16 $rn = REDIRECT_NODE
        $redir_mode -> *$rm
        @loc_dev($loc) -> *$rd
        @loc_node($loc) -> *$rn

        # Run command with output redirected
        @cmd_exec($line)

        # Reset redirection mode
        0 -> *$rm
        return
    }

    ram ptr u8 $cmd = $line
    ? *$cmd == 0 { return }
    ram imut $raw: u16 = @_split($line)
    ? @_streq($cmd, "set") == 1 { @cmd_set($raw) return }
    ? @_streq($cmd, "if") == 1 { @cmd_if($raw) return }
    ? @_streq($cmd, "rep") == 1 { @cmd_repeat($raw) return }
    ram mut $arg: u16 = 0
    ? $raw != 0 {
        @_expand($raw, EXPAND)
        EXPAND -> $arg
    }
    ? @_streq($cmd, "ps") == 1 { @cmd_ps() return }
    ? @_streq($cmd, "up") == 1 { @cmd_uptime() return }
    ? @_streq($cmd, "cls") == 1 { @cmd_clear() return }
    ? @_streq($cmd, "say") == 1 { @cmd_say($arg) return }
    ? @_streq($cmd, "pwd") == 1 { @cmd_pwd() return }
    ? @_streq($cmd, "cd") == 1 { @cmd_cd($arg) return }
    ? @_streq($cmd, "ls") == 1 { @cmd_ls($arg) return }
    ? @_streq($cmd, "mkd") == 1 { @cmd_mkdir($arg) return }
    ? @_streq($cmd, "new") == 1 { @cmd_new($arg) return }
    ? @_streq($cmd, "cat") == 1 { @cmd_cat($arg) return }
    ? @_streq($cmd, "rm") == 1 { @cmd_rm($arg) return }
    ? @_streq($cmd, "cp") == 1 { @cmd_cp($arg) return }
    ? @_streq($cmd, "mv") == 1 { @cmd_mv($arg) return }
    ? @_streq($cmd, "fmt") == 1 { @cmd_fmt($arg) return }
    ? @_streq($cmd, "mnt") == 1 { @cmd_mount($arg) return }
    ? @_streq($cmd, "umnt") == 1 { @cmd_umount($arg) return }
    ? @_streq($cmd, "run") == 1 { @cmd_run($arg) return }
    ? @_streq($cmd, "peek") == 1 { @cmd_peek($arg) return }
    ? @_streq($cmd, "poke") == 1 { @cmd_poke($arg) return }
    ? @_streq($cmd, "sbi") == 1 { @cmd_sbi($arg) return }
    ? @_streq($cmd, "cbi") == 1 { @cmd_cbi($arg) return }
    ? @_streq($cmd, "slp") == 1 { @cmd_slp($arg) return }
    ? @_streq($cmd, "spi") == 1 { @cmd_spi($arg) return }
    ? @_streq($cmd, "i2c") == 1 { @cmd_i2c($arg) return }
    ? @_streq($cmd, "adc") == 1 { @cmd_adc($arg) return }
    ? @_streq($cmd, "kill") == 1 { @cmd_kill($arg) return }
    @eperr()
}
