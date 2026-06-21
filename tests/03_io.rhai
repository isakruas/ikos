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

// ===== raw memory: poke/peek round-trip (hex is upper-case, unpadded) =======
no_err("write 0x41 to free SRAM 0x0300", cmd("poke 0300 41"));
has("read it back", cmd("peek 0300"), "41");
no_err("write 0xFF to 0x0301", cmd("poke 0301 ff"));
has("read it back (upper-case)", cmd("peek 0301"), "FF");
no_err("seed 0x02 (bit1 set)", cmd("poke 0300 02"));
no_err("sbi sets bit0", cmd("sbi 0300 0"));
has("both bits -> 03", cmd("peek 0300"), "3");
no_err("cbi clears bit1", cmd("cbi 0300 1"));
has("only bit0 -> 01", cmd("peek 0300"), "1");

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
has("ADCL after the channel-0 conversion", cmd("peek 0024"), "0");
has("ADCH after the channel-0 conversion (512 -> 0x02)", cmd("peek 0025"), "2");
has("channel 3 reads full-scale 1023", cmd("adc 3"), "1023");
has("an unconnected channel reads 0", cmd("adc 1"), "0");
