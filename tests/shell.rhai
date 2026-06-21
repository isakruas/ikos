// ikOS kernel shell tests.
//
// The full end-to-end shell suite. It boots the real kernel image in the
// simulator, drives the interactive shell over the virtual UART by injecting
// keystrokes, and asserts on what the kernel prints back — exercising both
// directions of every bus (UART, SPI, I2C, ADC, GPIO) plus the filesystem,
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
// Helpers — run a command, strip the echo/prompt, evaluate.
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
has_all("help lists the command set, incl. adc", cmd("help"), ["cmds: ls cd pwd", " adc "]);
has("mem: only the shell process is live", cmd("mem"), "P: 1/3");
has("uptime: tick counter prints", cmd("uptime"), "T: ");
has("ps: shell shows as running", cmd("ps"), "0 ");
has_raw("clear emits the screen-clear escape", cmd("clear"), "\x1b[2J");

// ===== echo, variables, arithmetic, $ expansion ============================
has("echo prints its argument", cmd("echo hello world"), "hello world");
no_err("set x 5: assign a variable", cmd("set x 5"));
has("$x expands to its value", cmd("echo $x"), "5");
no_err("set y = (5+3)*2 (left-to-right)", cmd("set y $x + 3 * 2"));
has("y = 16", cmd("echo $y"), "16");
no_err("set z = 100 / 4 (division)", cmd("set z 100 / 4"));
has("z = 25, mixed with literal text", cmd("echo val $z"), "val 25");

// ===== conditionals (every operator) + loops ===============================
has("gt true runs the command", cmd("if 5 gt 3 echo gt"), "gt");
not_has("gt false runs nothing", cmd("if 2 gt 9 echo no"), "no");
has("eq true", cmd("if 4 eq 4 echo eq"), "eq");
not_has("ne false", cmd("if 4 ne 4 echo no"), "no");
has("le true (equal)", cmd("if 3 le 3 echo le"), "le");
not_has("ge false", cmd("if 7 ge 9 echo no"), "no");
has("lt true", cmd("if 1 lt 2 echo lt"), "lt");
count_is("repeat runs n times", cmd("repeat 3 echo hi"), "hi", 3);
not_has("repeat 0 runs nothing", cmd("repeat 0 echo no"), "no");

// ===== filesystem (root fs has few nodes, so each batch cleans up) ==========
no_err("mkdir d", cmd("mkdir d"));
has("ls lists it with a trailing slash", cmd("ls"), "d/");
no_err("new f: create an empty file", cmd("new f"));
no_err("append a line via '>>'", cmd("echo hello >> f"));
has("file holds the appended line", cmd("cat f"), "hello");
no_err("overwrite via '>'", cmd("echo world > f"));
has("now holds the overwritten line", cmd("cat f"), "world");
not_has("overwrite truncated the old content", cmd("cat f"), "hello");
no_err("cat + '>' creates a new file in a subdir", cmd("cat f > d/c"));
has("the new file has the redirected content", cmd("cat d/c"), "world");
no_err("cd into the subdir", cmd("cd d"));
has("pwd reflects it", cmd("pwd"), "/d");
has("read the file by its relative name", cmd("cat c"), "world");
no_err("ascend with ..", cmd("cd .."));
has("back at root", cmd("pwd"), "/");
has_all("tree shows the dir, file and a last-child connector", cmd("tree"), ["d", "f", "`-- "]);
// cp / mv
no_err("cp a file into a directory", cmd("cp f d"));
has("the copy has the content", cmd("cat d/f"), "world");
no_err("mkdir b", cmd("mkdir b"));
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
no_err("an 8-char name is the maximum, kept whole", cmd("mkdir longname"));
has("the full 8-char name is listed", cmd("ls"), "longname/");
no_err("cleanup", cmd("rm longname"));

// ===== raw memory: poke/peek round-trip (hex is upper-case, unpadded) =======
no_err("write 0x41 to SRAM 0x0060", cmd("poke 0060 41"));
has("read it back", cmd("peek 0060"), "41");
no_err("write 0xFF to 0x0061", cmd("poke 0061 ff"));
has("read it back (upper-case)", cmd("peek 0061"), "FF");

// ===== GPIO on every port ==================================================
no_err("drive PORTB0 high", cmd("pin b0 1"));
no_err("drive PORTC5 low", cmd("pin c5 0"));
no_err("drive PORTD4 high", cmd("pin d4 1"));

// ===== serial buses against the assets/devices bench =======================
has("spi_echo returns mosi+1 = 0x42", cmd("spi 41"), "0x42");
has("0x00 -> 0x01 (hex unpadded)", cmd("spi 00"), "0x1");
has("at24c256 ACKs the write", cmd("i2c w 50 05"), "ok");
has("I2C read returns a byte", cmd("i2c r 50"), "0x");
// observe the MOSI side too: the MCU must have shifted out the byte we asked for
spi_mosi();                                                  // drain prior traffic
let spi_reply = cmd("spi 41");
has("spi_echo returns 0x42 (again)", spi_reply, "0x42");
check("MCU shifted out 0x41 on MOSI", spi_mosi().contains(0x41));

// ===== ADC: per-channel reads of the injected analog inputs ================
has("channel 0 reads the injected 512", cmd("adc 0"), "512");
has("ADCL after the channel-0 conversion", cmd("peek 0078"), "0");
has("ADCH after the channel-0 conversion (512 -> 0x02)", cmd("peek 0079"), "2");
has("channel 3 reads full-scale 1023", cmd("adc 3"), "1023");
has("an unconnected channel reads 0", cmd("adc 1"), "0");

// ===== mount an on-chip EEPROM volume (DEV_ALT = 1) + persistence ===========
no_err("mountpoint", cmd("mkdir mnt"));
no_err("mount the 2nd on-chip EEPROM partition", cmd("mount 1 /mnt"));
no_err("create+write a file on the mounted volume", cmd("echo onalt >> /mnt/note"));
has("read it back through the mount", cmd("cat /mnt/note"), "onalt");
no_err("unmount", cmd("umount /mnt"));
has("gone from the bare mountpoint", cmd("cat /mnt/note"), "?");
no_err("remount the same device", cmd("mount 1 /mnt"));
has("data persisted on the EEPROM across remount", cmd("cat /mnt/note"), "onalt");
no_err("unmount again", cmd("umount /mnt"));
no_err("cleanup mountpoint", cmd("rm mnt"));

// ===== mount the external I2C EEPROM volume (DEV_I2C = 2) ===================
no_err("mountpoint for the external EEPROM", cmd("mkdir ext"));
no_err("format+mount the 24Cxx over TWI/I2C", cmd("mount 2 /ext"));
no_err("write a file that lives on the I2C EEPROM", cmd("echo i2cfs >> /ext/x"));
has("read it back over the I2C block driver", cmd("cat /ext/x"), "i2cfs");
no_err("unmount the external volume", cmd("umount /ext"));
no_err("cleanup mountpoint", cmd("rm ext"));

// ===== scripts: create with redirection, run, observe effects ==============
no_err("create the script file", cmd("new job"));
no_err("a line that sets a var by arithmetic", cmd("echo set s 6 * 7 >> job"));
no_err("a line that makes a dir", cmd("echo mkdir made >> job"));
no_err("run the script", cmd("run job"));
has("the script's `set s 6 * 7` persisted: s = 42", cmd("echo $s"), "42");
has("the script's mkdir took effect", cmd("ls"), "made/");
no_err("cleanup", cmd("rm made"));
no_err("cleanup", cmd("rm job"));
// background job: `&` runs it as a separate process; later commands give it CPU.
no_err("create the background script", cmd("new bgjob"));
no_err("fill it", cmd("echo mkdir bg >> bgjob"));
no_err("launch it in the background", cmd("run bgjob &"));
has("let the scheduler give the bg job some ticks", cmd("uptime"), "T: ");
has("the background job created its dir", cmd("ls"), "bg/");
no_err("cleanup", cmd("rm bg"));
no_err("cleanup", cmd("rm bgjob"));

// ===== error handling ======================================================
has("unknown command -> '?'", cmd("frobnicate"), "?");
has("cd into a missing dir errors", cmd("cd nope"), "?");
has("cat a missing file errors", cmd("cat nope"), "?");
has("kill an out-of-range pid errors", cmd("kill 9"), "?");

log("ikOS shell driven end-to-end over UART/SPI/I2C/ADC/GPIO");
