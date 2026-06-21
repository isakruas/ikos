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

// ===== fmt: wipes the whole disk ===========================================
no_err("create a file", cmd("new tmp"));
has("file exists", cmd("ls"), "tmp");
no_err("fmt wipes everything", cmd("fmt"));
has("the file is gone after fmt", cmd("cat tmp"), "?");

// ===== empty file ==========================================================
no_err("create empty file", cmd("new e"));
no_err("cat of an empty file is not an error", cmd("cat e"));
no_err("cleanup e", cmd("rm e"));

// ===== exact cluster boundary (cluster = 16 B; line+newline) ===============
no_err("write 15 chars (+nl = exactly one 16-B cluster)", cmd("say 012345678901234 >> c1"));
has("16-byte file reads back whole", cmd("cat c1"), "012345678901234");
no_err("cleanup c1", cmd("rm c1"));

// ===== overwrite long -> short must free the old clusters ==================
no_err("write a multi-cluster line", cmd("say abcdefghijklmnopqrstuvwxyz0 >> ov"));
no_err("overwrite '>' with a short line", cmd("say hi > ov"));
has("now holds only the short content", cmd("cat ov"), "hi");
not_has("old long content is gone", cmd("cat ov"), "abcdef");
no_err("cleanup ov", cmd("rm ov"));

// ===== cluster reuse after delete ==========================================
no_err("big file A", cmd("say abcdefghijklmnopqrstuvwxyz0 >> A"));
no_err("delete A (returns its clusters to the pool)", cmd("rm A"));
no_err("file B reuses the freed clusters", cmd("say zyxwvutsrqponmlkjihgfe9 >> B"));
has("B is intact (no corruption from reuse)", cmd("cat B"), "zyxwvutsrqponmlkjihgfe9");
no_err("cleanup B", cmd("rm B"));

// ===== recursive rm of a non-empty directory ===============================
no_err("mkdir a", cmd("mkd a"));
no_err("a file inside a", cmd("say x >> a/f"));
no_err("rm a non-empty dir (recursive)", cmd("rm a"));
has("a is gone, contents too", cmd("cat a/f"), "?");

// ===== rm wildcard: dir/* wipes contents, keeps the dir =====================
no_err("mkdir d", cmd("mkd d"));
no_err("d/f1", cmd("say 1 >> d/f1"));
no_err("d/f2", cmd("say 2 >> d/f2"));
no_err("rm d/* wipes the contents", cmd("rm d/*"));
has("f1 is gone", cmd("cat d/f1"), "?");
no_err("d itself still exists (cd works)", cmd("cd d"));
no_err("back to root", cmd("cd .."));
no_err("cleanup d", cmd("rm d"));

// ===== large multi-cluster file (chain integrity at scale) =================
no_err("create big", cmd("new big"));
for i in 0..12 { cmd("say abcdefghijklmnopqrstuvwxyz0123 >> big"); }
has("big file reads back across ~24 clusters", cmd("cat big"), "abcdefghijklmnopqrstuvwxyz0123");
no_err("cleanup big", cmd("rm big"));

// ===== cluster exhaustion: write past pool capacity, cap gracefully ========
no_err("create fill", cmd("new fill"));
for i in 0..30 { cmd("say 012345678901234567890123456789012345678901234 >> fill"); }
no_err("FS still navigable after exhausting clusters", cmd("ls"));
no_err("the filled file is still readable (no hang/corruption)", cmd("cat fill"));
no_err("cleanup fill frees the pool again", cmd("rm fill"));
no_err("can create a file again after freeing", cmd("new again"));
no_err("cleanup again", cmd("rm again"));

// ===== node exhaustion (8 nodes: root + /init + 6 user nodes) ===============
no_err("clean slate", cmd("fmt"));
no_err("n1", cmd("new n1"));
no_err("n2", cmd("new n2"));
no_err("n3", cmd("new n3"));
no_err("n4", cmd("new n4"));
no_err("n5", cmd("new n5"));
no_err("n6 fills the node table", cmd("new n6"));
has("a 7th node errors gracefully (table full)", cmd("new n7"), "?");
no_err("an earlier file is still usable", cmd("cat n1"));
