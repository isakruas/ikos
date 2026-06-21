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

// ===== introspection =======================================================
has("uptime: tick counter prints", cmd("up"), "T: ");
has("ps: shell shows as running", cmd("ps"), "0 ");
no_err("slp 3: shell sleeps then returns a prompt", cmd("slp 3"));
has("shell responsive after sleeping", cmd("say back"), "back");
has_raw("clear emits the screen-clear escape", cmd("cls"), "\x1b[2J");

// ===== say, variables, arithmetic, $ expansion ============================
has("say prints its argument", cmd("say hello world"), "hello world");
no_err("set x 5: assign a variable", cmd("set x 5"));
has("$x expands to its value", cmd("say $x"), "5");
no_err("set y = (5+3)*2 (left-to-right)", cmd("set y $x + 3 * 2"));
has("y = 16", cmd("say $y"), "16");
no_err("set z = 100 / 4 (division)", cmd("set z 100 / 4"));
has("z = 25, mixed with literal text", cmd("say val $z"), "val 25");

// ===== conditionals (every operator) + loops ===============================
has("gt true runs the command", cmd("if 5 gt 3 say gt"), "gt");
not_has("gt false runs nothing", cmd("if 2 gt 9 say no"), "no");
has("eq true", cmd("if 4 eq 4 say eq"), "eq");
not_has("ne false", cmd("if 4 ne 4 say no"), "no");
has("le true (equal)", cmd("if 3 le 3 say le"), "le");
not_has("ge false", cmd("if 7 ge 9 say no"), "no");
has("lt true", cmd("if 1 lt 2 say lt"), "lt");
count_is("repeat runs n times", cmd("rep 3 say hi"), "hi", 3);
not_has("repeat 0 runs nothing", cmd("rep 0 say no"), "no");
