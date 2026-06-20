// ik-os - end-to-end shell test harness.
// Copyright (C) 2026 The IK-OS Authors
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Boots an ik-os HEX image inside the ik8bvm simulator (the same engine the
// IKIDE breadboard uses), drives the interactive shell over the *virtual* UART
// by injecting keystrokes, and asserts on what the kernel prints back.
//
// It does NOT re-implement anything: the VM, the `build_vm` device-table setup,
// and the Rhai device loader are imported straight from the existing crates
// (`ik8bvm` and `ikide`). The bus "bench" is built from the real
// assets/devices/*.rhai scripts via the IDE's ScriptedDevice/DeviceBus/SharedBus,
// so `spi`/`i2c` talk to the very same device models the IDE ships.
//
// Usage:  cargo run --release -- [path/to/boot.hex]   (default: ../build/boot.hex)

use ik8bvm::core::{AvrVm, IoPeripheral};
use ikide::core::devices::{engine, DeviceBus, ScriptedDevice, SharedBus};
use ikide::core::runner::build_vm;
use std::collections::HashMap;
use std::sync::{Arc, Mutex};

// ik-os ships targeting the atmega328p (see boot.ik).
const TARGET: &str = "atmega328p";

// The shell submits a line on CR (0x0D), echoes printable input, and ends every
// prompt with "$ " — see shell/shell.ik (`@_key`, `@_prompt`).
const CR: u8 = b'\r';
const PROMPT_TAIL: &str = "$ ";

// Generous per-command instruction ceiling; real commands finish far sooner and
// the prompt-detection below breaks the loop early.
const STEP_CHUNK: u64 = 50_000;
// Higher than a normal command needs: formatting the external I2C EEPROM on
// `mount 2` writes the whole node table one TWI byte-transaction at a time.
const CMD_BUDGET: u64 = 60_000_000;
const BOOT_BUDGET: u64 = 40_000_000;

// The standard bench, assembled from real assets/devices scripts (paths are
// relative to ik-os/test, where cargo runs the binary):
//   spi_echo.rhai  — SPI returns mosi+1
//   at24c256.rhai  — 32 KB I2C EEPROM at 0x50 with 16-bit word addressing, which
//                    is exactly what the kernel's DEV_I2C block driver expects,
//                    so `mount 2` (external EEPROM filesystem) has real storage.
const BENCH_DEVICES: &[&str] = &[
    "../tools/ikide/assets/devices/spi_echo.rhai",
    "../tools/ikide/assets/devices/at24c256.rhai",
];

// ADC inputs the bench presents (channel -> 10-bit value), injected before the
// session so `adc <ch>` reads them back. Mirrors a potentiometer on a pin.
const ADC_INPUTS: &[(u8, u16)] = &[(0, 512), (3, 1023)];

/// Load the bench devices into the IDE's DeviceBus (shared with the VM through
/// SharedBus, which is itself a `BusResponder`).
fn build_bench(target: &str) -> Result<(Arc<Mutex<DeviceBus>>, String), String> {
    let eng = engine();
    let wiring: HashMap<String, String> = HashMap::new();
    let mut bus = DeviceBus::default();
    let mut names = Vec::new();
    for path in BENCH_DEVICES {
        let src = std::fs::read_to_string(path).map_err(|e| format!("{}: {}", path, e))?;
        bus.add(ScriptedDevice::from_src(eng.clone(), &src, target, &wiring)?);
        names.push(path.rsplit('/').next().unwrap_or(path).to_string());
    }
    Ok((Arc::new(Mutex::new(bus)), names.join(" + ")))
}

// ---------------------------------------------------------------------------
// UART driving (the bits sim_live.rs does per frame, minus the GUI).
// ---------------------------------------------------------------------------

/// Drain UART transmit bytes the kernel produced since the last call into `out`.
fn drain_uart(vm: &mut AvrVm, out: &mut String) {
    let events = std::mem::take(&mut vm.io_events);
    for e in events {
        if e.periph == IoPeripheral::Uart && e.write {
            out.push(e.byte as char);
        }
    }
}

/// Step until the shell prints a fresh prompt with all fed input consumed, or a
/// budget is hit. Returns everything the kernel transmitted in that window.
fn run_until_prompt(vm: &mut AvrVm, budget: u64) -> String {
    let mut out = String::new();
    let mut spent = 0u64;
    loop {
        for _ in 0..STEP_CHUNK {
            if !vm.running {
                break;
            }
            vm.step();
        }
        spent += STEP_CHUNK;
        drain_uart(vm, &mut out);

        if vm.uart_rx.is_empty() && out.ends_with(PROMPT_TAIL) {
            break;
        }
        if !vm.running || spent >= budget {
            break;
        }
    }
    out
}

/// Type a command line + CR and collect the kernel's reply up to the next prompt.
fn run_command(vm: &mut AvrVm, line: &str) -> String {
    vm.uart_feed(line.as_bytes());
    vm.uart_feed(&[CR]);
    run_until_prompt(vm, CMD_BUDGET)
}

/// Strip the echoed command line (everything up to the first newline) and the
/// trailing prompt (everything after the last newline), leaving just the body
/// the command actually printed.
fn body_of(raw: &str) -> String {
    let first = raw.find('\n');
    let last = raw.rfind('\n');
    match (first, last) {
        (Some(f), Some(l)) if l > f => raw[f + 1..l].to_string(),
        _ => String::new(),
    }
}

// ---------------------------------------------------------------------------
// Test specification.
// ---------------------------------------------------------------------------
enum Check {
    /// Command body must contain this substring.
    Has(&'static str),
    /// Command body must contain every substring.
    HasAll(&'static [&'static str]),
    /// Command body must NOT contain this substring.
    NotHas(&'static str),
    /// Substring must appear exactly N times in the body.
    Count(&'static str, usize),
    /// Body must carry no error reply ("?", from @eperr).
    NoErr,
    /// Raw (un-stripped) output must contain this — for commands whose reply has
    /// no trailing newline before the prompt (e.g. `clear`).
    HasRaw(&'static str),
}

struct Case {
    cmd: &'static str,
    note: &'static str,
    check: Check,
}

fn cases() -> Vec<Case> {
    use Check::*;
    macro_rules! c {
        ($cmd:expr, $note:expr, $check:expr) => {
            Case { cmd: $cmd, note: $note, check: $check }
        };
    }
    vec![
        // ===== introspection =====
        c!("help", "lists the command set, including adc",
            HasAll(&["cmds: ls cd pwd", " adc "])),
        c!("mem", "only the shell process is live", Has("P: 1/3")),
        c!("uptime", "tick counter prints", Has("T: ")),
        c!("ps", "shell shows as running (proc 0, state X)", Has("0 ")),
        c!("clear", "clear emits the screen-clear escape", HasRaw("\x1b[2J")),

        // ===== echo, variables, arithmetic, $ expansion =====
        c!("echo hello world", "echo prints its argument", Has("hello world")),
        c!("set x 5", "assign a variable", NoErr),
        c!("echo $x", "$x expands to its value", Has("5")),
        c!("set y $x + 3 * 2", "expr is left-to-right: (5+3)*2", NoErr),
        c!("echo $y", "y = 16", Has("16")),
        c!("set z 100 / 4", "division", NoErr),
        c!("echo val $z", "z = 25, mixed with literal text", Has("val 25")),

        // ===== conditionals (every operator) + loops =====
        c!("if 5 gt 3 echo gt", "gt true runs the command", Has("gt")),
        c!("if 2 gt 9 echo no", "gt false runs nothing", NotHas("no")),
        c!("if 4 eq 4 echo eq", "eq true", Has("eq")),
        c!("if 4 ne 4 echo no", "ne false", NotHas("no")),
        c!("if 3 le 3 echo le", "le true (equal)", Has("le")),
        c!("if 7 ge 9 echo no", "ge false", NotHas("no")),
        c!("if 1 lt 2 echo lt", "lt true", Has("lt")),
        c!("repeat 3 echo hi", "repeat runs n times", Count("hi", 3)),
        c!("repeat 0 echo no", "repeat 0 runs nothing", NotHas("no")),

        // ===== filesystem (root fs = only 8 nodes, so each batch cleans up) =====
        // dirs / files / redirection / cat-into-a-new-file-in-a-subdir
        c!("mkdir d", "make a directory", NoErr),
        c!("ls", "it is listed with a trailing slash", Has("d/")),
        c!("new f", "create an empty file", NoErr),
        c!("echo hello >> f", "append a line via '>>'", NoErr),
        c!("cat f", "file holds the appended line", Has("hello")),
        c!("echo world > f", "overwrite via '>'", NoErr),
        c!("cat f", "now holds the overwritten line", Has("world")),
        c!("cat f", "overwrite truncated the old content", NotHas("hello")),
        // `>` creates the target if missing — here a new file inside a subdir.
        c!("cat f > d/c", "cat + '>' creates a new file in a subdir", NoErr),
        c!("cat d/c", "the new file has the redirected content", Has("world")),
        c!("cd d", "descend into the subdir", NoErr),
        c!("pwd", "pwd reflects it", Has("/d")),
        c!("cat c", "read the file by its relative name", Has("world")),
        c!("cd ..", "ascend with ..", NoErr),
        c!("pwd", "back at root", Has("/")),
        c!("tree", "tree shows the dir, file and a last-child connector",
            HasAll(&["d", "f", "`-- "])),
        // cp / mv
        c!("cp f d", "copy a file into a directory", NoErr),
        c!("cat d/f", "the copy has the content", Has("world")),
        c!("mkdir b", "another dir", NoErr),
        c!("mv f b", "move a file into a directory", NoErr),
        c!("cat b/f", "reachable at the new path", Has("world")),
        c!("cat f", "and gone from the old path", Has("?")),
        // cleanup this batch (rm a non-empty dir errors, so empty children first)
        c!("rm b/f", "remove the moved file", NoErr),
        c!("rm b", "remove the now-empty dir", NoErr),
        c!("rm d/f", "remove the copy", NoErr),
        c!("rm d/c", "remove the redirected file", NoErr),
        c!("rm d", "remove the now-empty subdir", NoErr),
        c!("rm f", "rm a missing file errors", Has("?")),

        // ===== name length boundary (FS_NAMELEN = 8) =====
        c!("mkdir longname", "an 8-char name is the maximum, kept whole", NoErr),
        c!("ls", "the full 8-char name is listed", Has("longname/")),
        c!("rm longname", "cleanup", NoErr),

        // ===== raw memory: poke/peek round-trip (hex is upper-case, unpadded) =====
        c!("poke 0060 41", "write 0x41 to SRAM 0x0060", NoErr),
        c!("peek 0060", "read it back", Has("41")),
        c!("poke 0061 ff", "write 0xFF to 0x0061", NoErr),
        c!("peek 0061", "read it back (upper-case)", Has("FF")),

        // ===== GPIO on every port =====
        c!("pin b0 1", "drive PORTB0 high", NoErr),
        c!("pin c5 0", "drive PORTC5 low", NoErr),
        c!("pin d4 1", "drive PORTD4 high", NoErr),

        // ===== serial buses against the assets/devices bench =====
        c!("spi 41", "spi_echo.rhai returns mosi+1 = 0x42", Has("0x42")),
        c!("spi 00", "0x00 -> 0x01 (hex unpadded)", Has("0x1")),
        c!("i2c w 50 05", "at24c256.rhai ACKs the write", Has("ok")),
        c!("i2c r 50", "I2C read returns a byte", Has("0x")),

        // ===== ADC: per-channel reads of the injected analog inputs =====
        c!("adc 0", "channel 0 reads the injected 512", Has("512")),
        // Diagnostic: after the conversion above, ADCL=0x78 / ADCH=0x79 hold the
        // raw result the sim latched. If these read 00 / 02 the latch is right
        // and any wrong `adc` value is in the combine; otherwise it's the model.
        c!("peek 0078", "ADCL after the channel-0 conversion", Has("0")),
        c!("peek 0079", "ADCH after the channel-0 conversion (512 -> 0x02)", Has("2")),
        c!("adc 3", "channel 3 reads full-scale 1023", Has("1023")),
        c!("adc 1", "an unconnected channel reads 0", Has("0")),

        // ===== mount an on-chip EEPROM volume (DEV_ALT = 1) + persistence =====
        c!("mkdir mnt", "mountpoint", NoErr),
        c!("mount 1 /mnt", "mount the 2nd on-chip EEPROM partition", NoErr),
        c!("echo onalt >> /mnt/note", "create+write a file on the mounted volume", NoErr),
        c!("cat /mnt/note", "read it back through the mount", Has("onalt")),
        c!("umount /mnt", "unmount", NoErr),
        c!("cat /mnt/note", "gone from the bare mountpoint", Has("?")),
        c!("mount 1 /mnt", "remount the same device", NoErr),
        c!("cat /mnt/note", "data persisted on the EEPROM across remount", Has("onalt")),
        c!("umount /mnt", "unmount again", NoErr),
        c!("rm mnt", "cleanup mountpoint", NoErr),

        // ===== mount the external I2C EEPROM volume (DEV_I2C = 2) =====
        c!("mkdir ext", "mountpoint for the external EEPROM", NoErr),
        c!("mount 2 /ext", "format+mount the 24Cxx over TWI/I2C", NoErr),
        c!("echo i2cfs >> /ext/x", "write a file that lives on the I2C EEPROM", NoErr),
        c!("cat /ext/x", "read it back over the I2C block driver", Has("i2cfs")),
        c!("umount /ext", "unmount the external volume", NoErr),
        c!("rm ext", "cleanup mountpoint", NoErr),

        // ===== scripts: create with redirection, run, observe effects =====
        c!("new job", "create the script file", NoErr),
        c!("echo set s 6 * 7 >> job", "a line that sets a var by arithmetic", NoErr),
        c!("echo mkdir made >> job", "a line that makes a dir", NoErr),
        c!("run job", "run the script", NoErr),
        c!("echo $s", "the script's `set s 6 * 7` persisted: s = 42", Has("42")),
        c!("ls", "the script's mkdir took effect", Has("made/")),
        c!("rm made", "cleanup", NoErr),
        c!("rm job", "cleanup", NoErr),
        // background job: `&` runs it as a separate process; later commands give
        // it CPU, so its mkdir appears by the time we list.
        c!("new bgjob", "create the background script", NoErr),
        c!("echo mkdir bg >> bgjob", "fill it", NoErr),
        c!("run bgjob &", "launch it in the background", NoErr),
        c!("uptime", "let the scheduler give the bg job some ticks", Has("T: ")),
        c!("ls", "the background job created its dir", Has("bg/")),
        c!("rm bg", "cleanup", NoErr),
        c!("rm bgjob", "cleanup", NoErr),

        // ===== error handling =====
        c!("frobnicate", "unknown command -> '?'", Has("?")),
        c!("cd nope", "cd into a missing dir errors", Has("?")),
        c!("cat nope", "cat a missing file errors", Has("?")),
        c!("kill 9", "kill an out-of-range pid errors", Has("?")),
    ]
}

fn evaluate(raw: &str, check: &Check) -> Result<(), String> {
    let body = body_of(raw);
    match check {
        Check::Has(s) => {
            if body.contains(s) { Ok(()) } else { Err(format!("expected to contain {:?}", s)) }
        }
        Check::HasAll(list) => {
            for s in *list {
                if !body.contains(s) {
                    return Err(format!("expected to contain {:?}", s));
                }
            }
            Ok(())
        }
        Check::NotHas(s) => {
            if body.contains(s) { Err(format!("expected NOT to contain {:?}", s)) } else { Ok(()) }
        }
        Check::Count(s, n) => {
            let got = body.matches(s).count();
            if got == *n { Ok(()) } else { Err(format!("expected {:?} x{}, found x{}", s, n, got)) }
        }
        Check::NoErr => {
            if body.contains('?') { Err("unexpected error reply '?'".to_string()) } else { Ok(()) }
        }
        Check::HasRaw(s) => {
            if raw.contains(s) { Ok(()) } else { Err(format!("expected raw output to contain {:?}", s)) }
        }
    }
}

/// Make control characters visible in the transcript.
fn visible(s: &str) -> String {
    let mut out = String::new();
    for ch in s.chars() {
        match ch {
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\x1b' => out.push_str("\\e"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\x{:02x}", c as u32)),
            c => out.push(c),
        }
    }
    out
}

fn main() {
    let hex_path = std::env::args().nth(1).unwrap_or_else(|| "../build/boot.hex".to_string());

    let (bus, bench_label) = match build_bench(TARGET) {
        Ok(b) => b,
        Err(e) => {
            eprintln!("FATAL: could not build the device bench: {}", e);
            std::process::exit(2);
        }
    };

    println!("ik-os shell test harness");
    println!("  hex    : {}", hex_path);
    println!("  device : {}", TARGET);
    println!("  bench  : {}\n", bench_label);

    let mut vm = build_vm(TARGET);
    if let Err(e) = ik8bvm::hw::load_hex(&mut vm, &hex_path) {
        eprintln!("FATAL: could not load HEX '{}': {}", hex_path, e);
        std::process::exit(2);
    }
    vm.capture_io = true;
    vm.watch_pins = bus.lock().unwrap().pin_addrs().into_iter().collect();
    vm.responder = Some(Box::new(SharedBus(bus.clone())));
    for &(ch, val) in ADC_INPUTS {
        vm.adc_set(ch as usize, val);
    }

    // Boot: run to the first prompt and show the banner / self-check log.
    let boot = run_until_prompt(&mut vm, BOOT_BUDGET);
    println!("--- boot ---");
    for line in boot.lines() {
        println!("  {}", line);
    }
    if !boot.ends_with(PROMPT_TAIL) {
        eprintln!("\nFATAL: kernel never reached the shell prompt (boot hung?).");
        std::process::exit(2);
    }
    println!("--- session ---");

    let mut passed = 0usize;
    let mut failed = 0usize;
    for case in cases() {
        let raw = run_command(&mut vm, case.cmd);
        match evaluate(&raw, &case.check) {
            Ok(()) => {
                passed += 1;
                println!("  PASS  {:<20} | {}", case.cmd, case.note);
            }
            Err(why) => {
                failed += 1;
                println!("  FAIL  {:<20} | {}", case.cmd, case.note);
                println!("        reason: {}", why);
                println!("        body  : {:?}", visible(&body_of(&raw)));
                println!("        raw   : {:?}", visible(&raw));
            }
        }
    }

    println!("\n{} passed, {} failed, {} total", passed, failed, passed + failed);
    std::process::exit(if failed == 0 { 0 } else { 1 });
}
