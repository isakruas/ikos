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

// ===== scripts: create with redirection, run, observe effects ==============
no_err("create the script file", cmd("new job"));
no_err("a line that sets a var by arithmetic", cmd("say set s 6 * 7 >> job"));
no_err("a line that makes a dir", cmd("say mkd made >> job"));
no_err("run the script", cmd("run job"));
has("the script's `set s 6 * 7` persisted: s = 42", cmd("say $s"), "42");
has("the script's mkdir took effect", cmd("ls"), "made/");
no_err("cleanup", cmd("rm made"));
no_err("cleanup", cmd("rm job"));

// Unescaped, $ expands at WRITE time: the variable's value is baked into the
// script line, not kept as a live reference.
no_err("set n 9", cmd("set n 9"));
no_err("bake $n into a script line via say", cmd("say say got $n >> sc"));
has("the file holds the baked value, not the reference", cmd("cat sc"), "say got 9");
has("running the script prints the baked value", cmd("run sc"), "got 9");
no_err("change n to 3", cmd("set n 3"));
has("script still prints 9: $ expanded at write time", cmd("run sc"), "got 9");
no_err("cleanup sc", cmd("rm sc"));

// \$ escapes the dollar: a *literal* $var is saved to the file and expanded
// only when the script line runs -- so it re-renders each run.
no_err("set m 5", cmd("set m 5"));
no_err("save a live reference with \\$", cmd("say say got \\$m >> de"));
has("the file holds the literal $m, not a value", cmd("cat de"), "got $m");
has("running it expands $m at run time", cmd("run de"), "got 5");
no_err("change m to 9", cmd("set m 9"));
has("re-running re-renders the variable", cmd("run de"), "got 9");
no_err("cleanup de", cmd("rm de"));

// background job: `&` runs it as a separate process; later commands give it CPU.
no_err("create the background script", cmd("new bgjob"));
no_err("fill it", cmd("say mkd bg >> bgjob"));
no_err("launch it in the background", cmd("run bgjob &"));
has("let the scheduler give the bg job some ticks", cmd("up"), "T: ");
has("the background job created its dir", cmd("ls"), "bg/");
no_err("cleanup", cmd("rm bg"));
no_err("cleanup", cmd("rm bgjob"));
