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

// ===== filesystem (root fs has few nodes, so each batch cleans up) ==========
no_err("mkdir d", cmd("mkd d"));
has("ls lists it with a trailing slash", cmd("ls"), "d/");
no_err("new f: create an empty file", cmd("new f"));
no_err("append a line via '>>'", cmd("say hello >> f"));
has("file holds the appended line", cmd("cat f"), "hello");
no_err("overwrite via '>'", cmd("say world > f"));
has("now holds the overwritten line", cmd("cat f"), "world");
not_has("overwrite truncated the old content", cmd("cat f"), "hello");
no_err("cat + '>' creates a new file in a subdir", cmd("cat f > d/c"));
has("the new file has the redirected content", cmd("cat d/c"), "world");
no_err("cd into the subdir", cmd("cd d"));
has("pwd reflects it", cmd("pwd"), "/d");
has("read the file by its relative name", cmd("cat c"), "world");
no_err("ascend with ..", cmd("cd .."));
has("back at root", cmd("pwd"), "/");
has_all("ls renders a tree: dir, file and a last-child connector", cmd("ls"), ["d", "f", "`-- "]);
// dynamic allocation: a file bigger than one 16-byte cluster must chain clusters
no_err("write a line spanning >1 cluster", cmd("say abcdefghijklmnopqrstuvwxyz01 >> big"));
has("the full multi-cluster content reads back", cmd("cat big"), "abcdefghijklmnopqrstuvwxyz01");
no_err("remove the multi-cluster file", cmd("rm big"));
// cp / mv
no_err("cp a file into a directory", cmd("cp f d"));
has("the copy has the content", cmd("cat d/f"), "world");
no_err("mkdir b", cmd("mkd b"));
no_err("mv a file into a directory", cmd("mv f b"));
has("reachable at the new path", cmd("cat b/f"), "world");
has("and gone from the old path", cmd("cat f"), "?");
// cleanup (rm a non-empty dir errors, so empty children first)
no_err("rm the moved file", cmd("rm b/f"));
no_err("rm the now-empty dir", cmd("rm b"));
no_err("rm the copy", cmd("rm d/f"));
no_err("rm the redirected file", cmd("rm d/c"));
no_err("rm the now-empty subdir", cmd("rm d"));
has("rm a missing file errors", cmd("rm f"), "?");

// ===== name length boundary (FS_NAMELEN = 8) ===============================
no_err("an 8-char name is the maximum, kept whole", cmd("mkd longname"));
has("the full 8-char name is listed", cmd("ls"), "longname/");
no_err("cleanup", cmd("rm longname"));
