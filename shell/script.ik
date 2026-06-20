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
# Script language: 26 integer variables (a..z), arithmetic, conditionals and a
# counted loop. `$x` anywhere in a command line expands to the value of variable
# x. Expressions are space-separated, evaluated left to right (no precedence):
# `set y $x + 3 * 2` is ((x+3)*2).

@var_get($idx: u8) -> u16 {
    ram imut $a: u16 = VARS + ($idx * 2)
    ram ptr u16 $p = $a
    return *$p
}
@var_set($idx: u8, $val: u16) {
    ram imut $a: u16 = VARS + ($idx * 2)
    ram ptr u16 $p = $a
    $val -> *$p
}

# Write the decimal form of $val into buffer $d at offset $di; return new offset.
@_putdec($d: u16, $di: u16, $val: u16) -> u16 {
    ram mut $tmp: u8[8] = 0
    @utoa($val, &$tmp[0])
    ram ptr u8 $dp = $d
    ram mut $j: u16 = 0
    loop 0..7 -> $m {
        ram imut $c: u8 = $tmp[$m]
        ? $c != 0 {
            $c -> *($dp + $di + $j)
            $j + 1 -> $j
        }
    }
    return $di + $j
}

# Copy $src to $dst, replacing each $<a-z> with the variable's decimal value.
@_expand($src: u16, $dst: u16) {
    ram ptr u8 $s = $src
    ram ptr u8 $d = $dst
    ram mut $si: u16 = 0
    ram mut $di: u16 = 0
    ram mut $done: u8 = 0
    loop 0..63 -> $k {
        ? $done == 0 {
            ram imut $c: u8 = *($s + $si)
            # Stop at end of string, or before a variable's decimal form (up to 5
            # digits) plus the NUL could run past EXPAND's 80 bytes into the mount table.
            ? $c == 0 { 1 -> $done }
            ? $di >= 74 { 1 -> $done }
            ? $done == 0 {
                ram imut $v: u8 = *($s + $si + 1)
                ram mut $isvar: u8 = 0
                ? $c == 36 {
                    ? $v >= 97 {
                        ? $v <= 122 { 1 -> $isvar }
                    }
                }
                ? $isvar == 1 {
                    @_putdec($d, $di, @var_get($v - 97)) -> $di
                    $si + 2 -> $si
                } : {
                    $c -> *($d + $di)
                    $di + 1 -> $di
                    $si + 1 -> $si
                }
            }
        }
    }
    0 -> *($d + $di)
}

@_apply($op: u8, $a: u16, $b: u16) -> u16 {
    ? $op == 45 { return $a - $b }
    ? $op == 42 { return $a * $b }
    ? $op == 47 {
        ? $b == 0 { return 0 }
        return $a / $b
    }
    return $a + $b
}

# Evaluate a numeric expression (digits and + - * / left to right).
@_eval($e: u16) -> u16 {
    ram ptr u8 $p = $e
    ram mut $acc: u16 = 0
    ram mut $op: u8 = 43
    ram mut $n: u16 = 0
    ram mut $innum: u8 = 0
    ram mut $done: u8 = 0
    loop 0..63 -> $i {
        ? $done == 0 {
            ram imut $c: u8 = *($p + $i)
            ram mut $isdig: u8 = 0
            ? $c >= 48 {
                ? $c <= 57 { 1 -> $isdig }
            }
            ? $isdig == 1 {
                $n * 10 + ($c - 48) -> $n
                1 -> $innum
            } : {
                ? $innum == 1 {
                    @_apply($op, $acc, $n) -> $acc
                    0 -> $n
                    0 -> $innum
                }
                ? $c == 0 { 1 -> $done }
                ? $c == 43 { 43 -> $op }
                ? $c == 45 { 45 -> $op }
                ? $c == 42 { 42 -> $op }
                ? $c == 47 { 47 -> $op }
            }
        }
    }
    return $acc
}

# Expand $vars in $src, then evaluate it.
@_xeval($src: u16) -> u16 {
    ? $src == 0 { return 0 }
    @_expand($src, EXPAND)
    return @_eval(EXPAND)
}

@cmd_set($arg: u16) {
    ? $arg == 0 {
        @eperr()
        return
    }
    ram imut $expr: u16 = @_split($arg)
    ram ptr u8 $vp = $arg
    ram imut $vc: u8 = *$vp
    ? $vc < 97 {
        @eperr()
        return
    }
    ? $vc > 122 {
        @eperr()
        return
    }
    @var_set($vc - 97, @_xeval($expr))
}

@_cond($o0: u8, $o1: u8, $a: u16, $b: u16) -> u8 {
    switch $o0 {
        101 -> { return $a == $b }
        110 -> { return $a != $b }
        108 -> {
            ? $o1 == 116 { return $a < $b }
            return $a <= $b
        }
        103 -> {
            ? $o1 == 116 { return $a > $b }
            return $a >= $b
        }
        * -> { return 0 }
    }
}

# if <a> <op> <b> <command...>   (op: eq ne lt gt le ge)
@cmd_if($arg: u16) {
    ? $arg == 0 {
        @eperr()
        return
    }
    ram imut $r1: u16 = @_split($arg)
    ? $r1 == 0 { return }
    ram imut $r2: u16 = @_split($r1)
    ? $r2 == 0 { return }
    ram imut $r3: u16 = @_split($r2)
    ? $r3 == 0 { return }
    ram imut $a: u16 = @_xeval($arg)
    ram imut $b: u16 = @_xeval($r2)
    ram ptr u8 $op = $r1
    ? @_cond(*$op, *($op + 1), $a, $b) == 1 {
        @cmd_exec($r3)
    }
}

# repeat <count> <command...>
@cmd_repeat($arg: u16) {
    ? $arg == 0 {
        @eperr()
        return
    }
    ram imut $cmd: u16 = @_split($arg)
    ? $cmd == 0 { return }
    ram mut $n: u16 = @_xeval($arg)
    ? $n > 1000 { 1000 -> $n }
    ram mut $i: u16 = 0
    loop * {
        ? $i >= $n { return }
        # The loop body is parsed destructively, so re-copy the pristine source
        # (still intact in the caller's buffer) into REPEAT_RUN each pass.
        @_copy($cmd, REPEAT_RUN)
        @cmd_exec(REPEAT_RUN)
        $i + 1 -> $i
    }
}
