<!-- Copyright (C) 2026 The ikOS Authors. SPDX-License-Identifier: GPL-3.0-or-later -->

# ikOS

A small multitasking kernel written in the **ik** language for 8-bit AVR. It
boots into an interactive shell over the UART with a small scripting language, a
filesystem on EEPROM, and commands for files, processes, memory, GPIO and the
serial buses (UART/SPI/I2C/ADC).

Meet **Iki**, the ikOS mascot — an ant. Ants are tiny yet accomplish great
feats by working together: no ant is in charge, each does its part and yields to
the colony. That is ikOS — a kernel small enough for 32 KB where processes are
scheduled cooperatively, each yielding the CPU to the others so the whole system
does real work.

```
       \   /
      (o o)
   ==(=======)==
      / | | \
```

Targets `atmega32` and `atmega328p`, selected at the top of `boot.ik`. The SRAM
map in `kernel/memory.ik` fits both, and `arch/timer.ik` is a small per-target
HAL (a `? target == ...` block per device); adding another AVR means adding its
timer block there.

## Build & run

```sh
git submodule update --init --recursive
make toolchain        # build the ik8b compiler in the submodule (once, after clone)
make build            # compile to build/boot.hex
make run              # compile and simulate
make test             # run the Rhai test suite (tests/*.rhai) via the IDE runner
```

Run from this directory so the `import` paths resolve. Drive the shell over the
UART at **9600 baud**; type `help` to list commands.

## Documentation

The full manual (user guide, kernel internals, command reference) is a Sphinx
project under [`docs/`](docs/) — build it with `cd docs && make html`.

## Layout

```
boot.ik              entry: banner, init subsystems, start shell, run scheduler
config.ik            tunables (process count, baud)
arch/cpu.ik          critical sections, context switch + stack bootstrap
arch/timer.ik        Timer0 tick driving uptime/sleep
drivers/serial.ik    UART console I/O, boot banner
drivers/bus.ik       SPI / I2C / ADC commands
kernel/memory.ik     SRAM map
kernel/sched.ik      process table + scheduler
kernel/syscall.ik    yield / sleep / exit
fs/block.ik          block-storage layer (device 0/1 = EEPROM partitions, 2 = I2C)
fs/mount.ik          mount table (a directory redirects to another device)
fs/treefs.ik         hierarchical filesystem (directory tree over a block device)
shell/shell.ik       line editor + REPL
shell/script.ik      variables, arithmetic, if/repeat
shell/commands.ik    command interpreter + script runner
```

## License

ikOS is free software, licensed under the **GNU General Public License v3.0 or
later** (GPL-3.0-or-later). See [LICENSE](LICENSE) for the full text.
