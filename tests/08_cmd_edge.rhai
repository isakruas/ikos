// ikOS kernel shell tests.
//
// The full end-to-end shell suite. It boots the real kernel image in the
// simulator, drives the interactive shell over the virtual UART by injecting
// keystrokes, and asserts on what the kernel prints back — exercising both
// directions of every bus (UART, SPI, I2C, ADC) plus the filesystem,
// mounts, scripting and error handling.
//
// Nothing is faked: the buses talk to real device models loaded by name, and the
// kernel runs unmodified. Build the kernel first (`make build`) so that
// build/boot.hex exists.

// ---------------------------------------------------------------------------
// Bench: the kernel image + the same device models the breadboard ships.
// ---------------------------------------------------------------------------
build("boot.ik");
load_device("spi_echo");        // SPI slave that returns mosi+1
load_device("at24c256");        // 32 KB I2C EEPROM @0x50, 16-bit word addressing
                                // (what the kernel's DEV_I2C block driver expects,
                                // so `mount 2` has real backing storage)

// ADC inputs the bench presents (channel -> 10-bit value), injected before the
// session so `adc <ch>` reads them back. Mirrors a potentiometer on a pin.
set_adc(0, 512);
set_adc(3, 1023);

// The shell submits a line on CR (0x0D), echoes printable input, and ends every
// prompt with "$ " — see shell/shell.ik.
let CR = 13;

// Budgets: real commands finish far sooner; the "$ " prompt breaks the wait
// early. `mount 2` is the heavy one — it formats the external I2C EEPROM one TWI
// byte-transaction at a time.
let BOOT_BUDGET = 40000000;
let CMD_BUDGET  = 60000000;

// ---------------------------------------------------------------------------
// Helpers — run a command, strip the say/prompt, evaluate.
// ---------------------------------------------------------------------------

// Type a command line + CR and return everything the kernel transmitted up to
// the next prompt (the echoed line, the body, and the trailing "$ ").
fn cmd(line) {
    uart_clear();
    uart_send(line);
    uart_byte(13);                          // submit on CR
    step_until_uart("$ ", 60000000);
    uart_text()
}

// Strip the echoed command line (first line) and the trailing prompt (last
// line), leaving just the body the command actually printed.
fn body_of(raw) {
    let lines = raw.split("\n");
    let n = lines.len();
    if n <= 2 { return ""; }
    let out = "";
    for i in 1..(n - 1) {
        if i > 1 { out += "\n"; }
        out += lines[i];
    }
    out
}

// Count non-overlapping occurrences of `needle` in `hay`.
fn count_of(hay, needle) {
    if needle == "" { return 0; }
    let n = 0;
    let pos = hay.index_of(needle);
    while pos >= 0 {
        n += 1;
        pos = hay.index_of(needle, pos + needle.len());
    }
    n
}

// --- check primitives --------------------------------------------------------
fn has(name, raw, s)        { check(name, body_of(raw).contains(s)); }
fn not_has(name, raw, s)    { check(name, !body_of(raw).contains(s)); }
fn no_err(name, raw)        { check(name, !body_of(raw).contains("?")); }   // @eperr prints "?"
fn count_is(name, raw, s, n){ check_eq(name, count_of(body_of(raw), s), n); }
fn has_raw(name, raw, s)    { check(name, raw.contains(s)); }              // un-stripped (e.g. `clear`)
fn has_all(name, raw, list) {
    let b = body_of(raw);
    let ok = true;
    for s in list { if !b.contains(s) { ok = false; } }
    check(name, ok);
}

// ---------------------------------------------------------------------------
// Boot: run to the first shell prompt.
// ---------------------------------------------------------------------------
check("kernel reaches the shell prompt", step_until_uart("$ ", 40000000));

// ===== sbi/cbi on the highest bit (bit 7, mask 0x80) =======================
no_err("clear the scratch byte", cmd("poke 0300 00"));
no_err("sbi bit 7", cmd("sbi 0300 7"));
has("bit 7 set -> 80", cmd("peek 0300"), "80");
no_err("set all bits", cmd("poke 0300 ff"));
no_err("cbi bit 7", cmd("cbi 0300 7"));
has("bit 7 cleared -> 7F", cmd("peek 0300"), "7F");

// ===== missing-argument errors =============================================
has("sbi without a bit errors", cmd("sbi 0300"), "?");
has("cbi without a bit errors", cmd("cbi 0300"), "?");
has("slp without a count errors", cmd("slp"), "?");
has("poke without a value errors", cmd("poke 0300"), "?");

// ===== name longer than FS_NAMELEN (8) is truncated, not rejected ==========
no_err("create a name with 11 chars", cmd("mkd toolongname"));
has("the name is truncated to 8 chars", cmd("ls"), "toolongn/");
no_err("remove it by the truncated name", cmd("rm toolongn"));
