# Lesson 7: Lab 2, Bare-Metal "Hello, World!" in Xtensa Assembly

> **Goal:** write, build, package and boot a complete ESP32 firmware with
> no SDK, no C, no RTOS and no esptool: 25 instructions, a 19-line linker
> script and an 83-line Python packer.
>
> Project folder: [`hello-asm/`](../hello-asm). Snippets are verbatim, with
> source line numbers.

## 7.1 The pipeline

```
 src/hello.s --as--> build/hello.o --ld + link.ld--> build/hello.elf
                                                         |
                                tools/mkimage.py <-------+
                                   |            |
                          build/hello.bin   build/flash.bin (4 MB, image @ 0x1000)
                                                 |
                                    qemu-system-xtensa -machine esp32
```

| File | Lines | Role | Background |
|---|---|---|---|
| [`src/hello.s`](../hello-asm/src/hello.s) | 107 | the firmware | Lessons 3, 6 |
| [`link.ld`](../hello-asm/link.ld) | 19 | where each section lives in memory | Lessons 3, 4 |
| [`tools/mkimage.py`](../hello-asm/tools/mkimage.py) | 83 | ELF -> ESP32 image + 4 MB flash image | Lesson 4 |
| [`Makefile`](../hello-asm/Makefile) | 33 | runs the steps above | - |

## 7.2 Build and run

```bash
# activate the environment first (Lesson 1, section 1.7)
cd ~/esp32-firmware/hello-asm
make            # assemble, link, package
make run        # boot in QEMU   (quit: Ctrl-A, then X)
make clean
```

Reference output:

```text
$ make
mkdir -p build
xtensa-esp32-elf-as -o build/hello.o src/hello.s
xtensa-esp32-elf-ld -T link.ld -o build/hello.elf build/hello.o
python3 tools/mkimage.py build/hello.elf build/hello.bin build/flash.bin

$ make run
qemu-system-xtensa -nographic -machine esp32 \
    -drive file=build/flash.bin,if=mtd,format=raw
Adding SPI flash device
ets Jul 29 2019 12:21:46

rst:0x1 (POWERON_RESET),boot:0x12 (SPI_FAST_FLASH_BOOT)
configsip: 0, SPIWP:0xee
clk_drv:0x00,q_drv:0x00,d_drv:0x00,cs0_drv:0x00,hd_drv:0x00,wp_drv:0x00
mode:DIO, clock div:2
load:0x3fff0000,len:52
load:0x40080400,len:100
entry 0x40080420
Hello, World! (from bare-metal Xtensa assembly)
```

The firmware image is 208 bytes. The Lab 1 FreeRTOS app is 136,256 bytes,
plus a bootloader and a partition table.

---

## 7.3 `src/hello.s`, line by line

### Header comment (lines 1-16)

Assembly has no variable names, so the header's register map is the most
useful comment.

`hello-asm/src/hello.s`, lines 11-16:

```asm
 11  # Register use:
 12  #   a2  pointer to the next character of the message
 13  #   a3  current character
 14  #   a4  watchdog unlock key, then UART0 status register address
 15  #   a5  zero (for the watchdogs), then UART0 TX FIFO fill level
 16  #   a6  watchdog register address, then UART0 TX FIFO address
```

`#` starts a comment in GNU as for Xtensa. Lower-case `.s` marks input
passed directly to `as`; capital `.S` conventionally means "run the C
preprocessor first", which happens only when assembling through `gcc`.

### Register addresses (lines 18-30)

`hello-asm/src/hello.s`, lines 22-30:

```asm
 22      .set TIMG0_WDTCONFIG0,  0x3FF5F048  # Timer Group 0 watchdog config
 23      .set TIMG0_WDTWPROTECT, 0x3FF5F064  # Timer Group 0 watchdog write-protect
 24      .set RTC_WDTCONFIG0,    0x3FF4808C  # RTC watchdog config
 25      .set RTC_WDTWPROTECT,   0x3FF480A4  # RTC watchdog write-protect
 26      .set WDT_UNLOCK_KEY,    0x50D83AA1  # value that unlocks either watchdog
 27      .set UART0_STATUS,      0x3FF4001C  # bits [23:16] = bytes in TX FIFO
 28      .set UART0_FIFO,        0x60000000  # write a byte here to transmit it
 29                                          # (AHB address; ESP32 errata say not
 30                                          # to use the 0x3FF40000 DPORT alias)
```

`.set NAME, value` defines an assemble-time constant (NASM: `equ`) and
reserves no memory. Values are from the TRM; Lesson 3.3 describes each
register. Transmission uses the AHB address `0x6000_0000` (line 28): the
errata warn that repeated writes to the `0x3FF4_0000` alias can be lost.

### The message (lines 32-38)

`hello-asm/src/hello.s`, lines 36-38:

```asm
 36      .section .rodata
 37  message:
 38      .asciz "Hello, World! (from bare-metal Xtensa assembly)\r\n"
```

* Line 36 selects `.rodata`, which `link.ld` line 18 places in DRAM at
  `0x3FFF_0000`.
* Line 38: `.asciz` emits the bytes plus a terminating `0`, which ends the
  print loop. `\r\n` (carriage return + line feed) is the serial-terminal
  line ending.
* IRAM supports only 32-bit loads; a byte load (`l8ui`) from IRAM raises
  `LoadStoreError` on real silicon. The string therefore cannot share IRAM
  with the code.

### The literal pool (lines 43-57)

`hello-asm/src/hello.s`, lines 43-57:

```asm
 43      .section .text
 44
 45  # Literal pool. An Xtensa instruction is at most 24 bits wide, so it cannot
 46  # carry a 32-bit constant. Constants live here and are fetched with l32r,
 47  # which addresses them relative to the PC. l32r can only look backwards and
 48  # needs 4-byte-aligned words, so the pool sits before the code, aligned.
 49      .align 4
 50  lit_wdt_key:        .word WDT_UNLOCK_KEY
 51  lit_timg0_wdtwp:    .word TIMG0_WDTWPROTECT
 52  lit_timg0_wdtcfg:   .word TIMG0_WDTCONFIG0
 53  lit_rtc_wdtwp:      .word RTC_WDTWPROTECT
 54  lit_rtc_wdtcfg:     .word RTC_WDTCONFIG0
 55  lit_message:        .word message        # the linker fills in the address
 56  lit_uart_status:    .word UART0_STATUS
 57  lit_uart_fifo:      .word UART0_FIFO
```

* Line 43 selects `.text`, which `link.ld` line 15 places in IRAM at
  `0x4008_0400`.
* Instructions are 16 or 24 bits wide and cannot hold a 32-bit address, so
  addresses are stored as `.word` data (NASM: `dd`) and loaded with `l32r`.
* `l32r` is PC-relative, reaches only backwards (up to 256 KB) and requires
  4-byte alignment; hence the pool precedes the code (line 49, `.align 4`).
* Line 55 is the only word unknown at assembly time. The assembler emits a
  *relocation*, which the linker resolves to `0x3FFF0000`.

### The entry point (lines 59-62)

`hello-asm/src/hello.s`, lines 59-62:

```asm
 59  # Entry point. Global so that link.ld's ENTRY(_start) can find it; the linker
 60  # stores its address in the ELF header and mkimage.py copies it to the image.
 61      .global _start
 62  _start:
```

The 8-word (32-byte) pool occupies `0x4008_0400-0x4008_041F`, so the entry
point `_start` is at `0x4008_0420` (`entry 0x40080420` in the ROM log), not
at the start of the segment.

### Step 1: disable the watchdogs (lines 64-80)

`hello-asm/src/hello.s`, lines 64-80:

```asm
 64  # Step 1: disable the watchdogs. Their config registers are write-protected:
 65  # write the key to WPROTECT, then 0 to CONFIG0, which clears the enable bit.
 66  # Xtensa may reorder memory accesses, so memw makes the unlock land first.
 67      l32r    a4, lit_wdt_key         # a4 = unlock key
 68      movi    a5, 0                   # a5 = 0
 69
 70      l32r    a6, lit_timg0_wdtwp
 71      s32i    a4, a6, 0               # unlock the Timer Group 0 watchdog
 72      memw
 73      l32r    a6, lit_timg0_wdtcfg
 74      s32i    a5, a6, 0               # disable it
 75
 76      l32r    a6, lit_rtc_wdtwp
 77      s32i    a4, a6, 0               # unlock the RTC watchdog
 78      memw
 79      l32r    a6, lit_rtc_wdtcfg
 80      s32i    a5, a6, 0               # disable it
```

* `l32r` loads a literal; `movi` loads a small constant (-2048 to 2047).
* `s32i a4, a6, 0` stores the 32-bit `a4` at `a6 + 0`. The destination
  address comes second, the reverse of NASM's `mov [addr], reg`.
* The watchdog config registers are **write-protected** against runaway
  code. Writing `0x50D83AA1` to `WPROTECT` unlocks them;
  writing `0` to `CONFIG0` then clears the enable bit (31) and the
  flash-boot-mode bit (14 for Timer Group, 10 for RTC).
* Lines 72 and 78, `memw`: the unlock must reach the watchdog before the
  disable. An Xtensa CPU may "perform ordinary load and store operations in
  any order"; only accesses separated by `memw` occur in program order (ISA
  Reference Manual, section 3.8.3). The watchdogs are independent, so no
  barrier is needed between line 74 and line 77.

> **Emulator vs. silicon:** QEMU does not arm the ROM's flash-boot
> watchdogs; with lines 64-80 deleted the program still works in QEMU
> (verified: no reset within 30 s). On a real ESP32 the ROM arms both
> watchdogs, and the chip would reset after a few seconds and print the
> message again, indefinitely. Emulator fidelity must be verified.

### Step 2: the print loop (lines 82-103)

`hello-asm/src/hello.s`, lines 82-103:

```asm
 82  # Step 2: send the message, one byte at a time.
 83      l32r    a2, lit_message         # a2 = &message[0]
 84      l32r    a4, lit_uart_status     # a4 = &UART0_STATUS
 85      l32r    a6, lit_uart_fifo       # a6 = &UART0_FIFO
 86
 87  next_char:
 88      l8ui    a3, a2, 0               # a3 = *a2 (load byte, zero-extended)
 89      beqz    a3, halt                # reached the terminating '\0'? stop
 90
 91  wait_for_room:
 92      memw                            # finish the previous FIFO write first,
 93                                      # so the status read below is current
 94      l32i    a5, a4, 0               # a5 = UART0_STATUS
 95      extui   a5, a5, 16, 8           # a5 = bits [23:16] = TX FIFO fill level
 96      bgeui   a5, 128, wait_for_room  # FIFO (128 bytes) full? check again
 97
 98      s32i    a3, a6, 0               # queue the byte for transmission
 99                                      # (no memw needed before it: the store
100                                      # cannot run until the branch above has
101                                      # seen the status value)
102      addi    a2, a2, 1               # advance to the next character
103      j       next_char
```

Lines 83-85 load the three addresses once, before the loop, which is
equivalent to:

```c
for (char *p = message; *p != '\0'; p++) {     // lines 87-89, 102-103
    while (UART0_TX_FIFO_COUNT >= 128) { }     // lines 91-96
    UART0_FIFO = *p;                           // line 98
}
```

* Line 88, `l8ui`: load an 8-bit byte, zero-extended to 32 bits.
* Line 89, `beqz`: branch if the register is zero. Xtensa has no flags
  register; branches compare registers directly.
* Line 92, `memw`: the byte stored on line 98 must reach the FIFO before
  line 94 reads the fill level; otherwise the count could be stale.
* Line 95, `extui a5, a5, 16, 8` ("extract unsigned immediate"):
  `(a5 >> 16) & 0xFF`, the TX FIFO fill level in bits [23:16].
* Line 96, `bgeui a5, 128, ...`: wait while the FIFO holds 128 bytes (full).
  `bgeui` encodes only a fixed table of immediates (Lesson 6.6); 128 is in
  it, 126 is not.
* Line 98 writes the byte (the FIFO uses only the low 8 bits). As
  lines 99-101 state, no `memw` is needed before it: the store executes only
  if the branch on line 96 falls through, which depends on the status read,
  and no CPU performs a store speculatively.

This is **polled I/O**: spin until the hardware is ready, then act.

### Step 3: halt (lines 105-107)

`hello-asm/src/hello.s`, lines 105-107:

```asm
105  # Step 3: nothing left to do. Spin forever.
106  halt:
107      j       halt
```

With no OS to return to, the CPU jumps to itself indefinitely.

---

## 7.4 `link.ld`

`hello-asm/link.ld`, lines 1-19:

```ld
  1  /* link.ld - tell the linker where the program lives in ESP32 memory.
  2   *
  3   * The ROM copies each loadable part of our image to the address chosen here,
  4   * so these must be RAM regions that the ROM is not using while it loads us.
  5   * ESP-IDF's own bootloader loads to the same two regions
  6   * (components/bootloader/subproject/main/ld/esp32/bootloader.ld).
  7   */
  8
  9  /* Record _start in the ELF header as the entry point. */
 10  ENTRY(_start)
 11
 12  SECTIONS
 13  {
 14      /* Code (and its literal pool) -> internal instruction RAM (IRAM). */
 15      .text   0x40080400 : { *(.text) }
 16
 17      /* The message string -> internal data RAM (DRAM). */
 18      .rodata 0x3FFF0000 : { *(.rodata) }
 19  }
```

* Line 10: `ENTRY(_start)` writes `_start`'s address into the ELF header
  (`e_entry`), where `mkimage.py` line 25 reads it.
* Line 15: output section `.text`, at `0x4008_0400`, collects every input
  `.text` (`*(.text)`).
* Line 18: `.rodata`, likewise, at `0x3FFF_0000`.
* Both regions are used by ESP-IDF's ROM-loaded bootloader, so they are known
  to be free while the ROM copies our image (Lesson 4.5).

Each output section becomes one loadable ELF **segment** (`PT_LOAD`):

```text
$ xtensa-esp32-elf-readelf -l build/hello.elf
  Type           Offset   VirtAddr   PhysAddr   FileSiz MemSiz  Flg Align
  LOAD           0x001000 0x3fff0000 0x3fff0000 0x00032 0x00032 R   0x1000
  LOAD           0x001400 0x40080400 0x40080400 0x00063 0x00063 R E 0x1000
```

`0x32` = 50 bytes of string; `0x63` = 99 bytes of pool + code. The
non-loadable sections (`.xtensa.info`, `.xt.prop`, symbols) are added by the
assembler for tools and debuggers; `mkimage.py` ignores them.

---

## 7.5 `tools/mkimage.py`

The script reimplements `esptool.py elf2image` using only the Python
standard library. Lesson 4.4 describes the output format.

### Arguments and input (lines 16-19)

`hello-asm/tools/mkimage.py`, lines 16-19:

```python
 16  elf_path, image_path, flash_path = sys.argv[1:4]
 17
 18  with open(elf_path, "rb") as f:
 19      elf = f.read()
```

### Step 1: read the ELF (lines 21-37)

`hello-asm/tools/mkimage.py`, lines 21-37:

```python
 21  # --- 1. Read the ELF file ---------------------------------------------------
 22  # From the ELF32 header: e_entry (offset 24) and e_phoff (offset 28), then
 23  # e_phentsize and e_phnum (offset 42): the program-header table location,
 24  # entry size and entry count.
 25  entry, phoff = struct.unpack_from("<II", elf, 24)
 26  phentsize, phnum = struct.unpack_from("<HH", elf, 42)
 27
 28  # Each program header describes a segment. The first five 32-bit fields are
 29  # p_type, p_offset (where the bytes are in the file), p_vaddr (where they go
 30  # in memory), p_paddr and p_filesz (how many bytes). Type 1 (PT_LOAD) marks
 31  # segments that must be loaded into memory.
 32  segments = []
 33  for i in range(phnum):
 34      p_type, p_offset, p_vaddr, _p_paddr, p_filesz = struct.unpack_from(
 35          "<5I", elf, phoff + i * phentsize)
 36      if p_type == 1:
 37          segments.append((p_vaddr, elf[p_offset:p_offset + p_filesz]))
```

`struct.unpack_from("<II", elf, 24)` reads two little-endian (`<`) unsigned
32-bit integers (`I`) at byte offset 24. The offsets are defined in the ELF
specification (`docs/references/elf_spec_tis_1.2.pdf`).

### Step 2: the 24-byte header (lines 39-56)

`hello-asm/tools/mkimage.py`, lines 39-56:

```python
 39  # --- 2. Image header (24 bytes, little-endian) ------------------------------
 40  image = bytearray(struct.pack(
 41      "<BBBBIB3sHBHH4sB",
 42      0xE9,            # magic number; the ROM refuses anything else
 43      len(segments),   # segment count
 44      2,               # SPI flash mode: 2 = DIO
 45      0x20,            # high nibble: flash size (2 = 4 MB);
 46                       # low nibble: flash clock (0 = 40 MHz)
 47      entry,           # address the ROM jumps to
 48      0xEE,            # write-protect pin: 0xEE = none
 49      b"\x00" * 3,     # SPI pin drive strengths: defaults
 50      0,               # chip ID: 0 = ESP32
 51      0,               # minimum chip revision (legacy field)
 52      0,               # minimum chip revision (major * 100 + minor)
 53      0xFFFF,          # maximum chip revision: 0xFFFF = no limit
 54      b"\x00" * 4,     # reserved
 55      0,               # 1 would mean a SHA-256 digest follows the image
 56  ))
```

The format string on line 41 has one code per field: `B` = 1 byte,
`H` = 2 bytes, `I` = 4 bytes, `3s`/`4s` = raw bytes. Total:
1+1+1+1+4+1+3+2+1+2+2+4+1 = 24.

### Step 3: segments and checksum (lines 58-67)

`hello-asm/tools/mkimage.py`, lines 58-67:

```python
 58  # --- 3. Segments ------------------------------------------------------------
 59  # Each segment is: load address, length, data. Lengths must be multiples of
 60  # 4, so data is zero-padded. The checksum starts at 0xEF and XORs in every
 61  # data byte (headers are not included).
 62  checksum = 0xEF
 63  for address, data in segments:
 64      data += b"\x00" * (-len(data) % 4)
 65      image += struct.pack("<II", address, len(data)) + data
 66      for byte in data:
 67          checksum ^= byte
```

The 50-byte string is padded by line 64 to 52 (`len:52` in the ROM log);
the 99-byte code to 100 (`len:100`).

### Step 4: finish the image (lines 69-75)

`hello-asm/tools/mkimage.py`, lines 69-75:

```python
 69  # --- 4. Checksum ------------------------------------------------------------
 70  # Zero-pad so that the checksum byte ends the image on a 16-byte boundary.
 71  image += b"\x00" * (15 - len(image) % 16)
 72  image.append(checksum)
 73
 74  with open(image_path, "wb") as f:
 75      f.write(image)
```

### Step 5: the flash image (lines 77-83)

`hello-asm/tools/mkimage.py`, lines 77-83:

```python
 77  # --- 5. Flash image ---------------------------------------------------------
 78  # Erased flash reads as 0xFF. The ROM looks for an image at offset 0x1000.
 79  flash = bytearray(b"\xFF" * (4 * 1024 * 1024))
 80  flash[0x1000:0x1000 + len(image)] = image
 81
 82  with open(flash_path, "wb") as f:
 83      f.write(flash)
```

QEMU emulates the flash chip and therefore needs the full 4 MB. A real board
is programmed with `hello.bin` alone, at offset `0x1000`.

### Verifying the packer

```bash
esptool.py --chip esp32 image_info --version 2 build/hello.bin
#   ...  Checksum: 0x5 (valid)
esptool.py --chip esp32 elf2image --dont-append-digest \
    --flash_mode dio --flash_size 4MB -o /tmp/ref.bin build/hello.elf
cmp build/hello.bin /tmp/ref.bin && echo IDENTICAL       # -> IDENTICAL
```

---

## 7.6 `Makefile`

`hello-asm/Makefile`, lines 9-33:

```make
  9  # Plain `make` builds the flash image (otherwise make builds the first rule).
 10  .DEFAULT_GOAL := build/flash.bin
 11
 12  # Assemble: turn source text into machine code (an object file).
 13  build/hello.o: src/hello.s
 14  	mkdir -p build
 15  	xtensa-esp32-elf-as -o $@ $<
 16
 17  # Link: give every section its final address, using link.ld.
 18  build/hello.elf: build/hello.o link.ld
 19  	xtensa-esp32-elf-ld -T link.ld -o $@ $<
 20
 21  # Package: convert the ELF into a bootable ESP32 image and a flash image.
 22  build/flash.bin: build/hello.elf tools/mkimage.py
 23  	python3 tools/mkimage.py $< build/hello.bin $@
 24
 25  # Boot the flash image on an emulated ESP32. Quit with Ctrl-A, then X.
 26  run: build/flash.bin
 27  	qemu-system-xtensa -nographic -machine esp32 \
 28  	    -drive file=$<,if=mtd,format=raw
 29
 30  clean:
 31  	rm -rf build
 32
 33  .PHONY: run clean
```

* Each rule is `target: prerequisites` plus tab-indented commands, re-run
  only if a prerequisite is newer than the target.
* `$@` = the target, `$<` = the first prerequisite.
* Line 10: without it, plain `make` would build only the first rule
  (`build/hello.o`).
* Line 23: one command produces both `hello.bin` and `flash.bin`; Make
  tracks `flash.bin`.
* Lines 27-28: the QEMU command from Lab 1. `-machine esp32` selects
  Espressif's board model; `if=mtd` attaches the file as SPI flash.

---

## 7.7 Reading the machine code

```text
$ xtensa-esp32-elf-objdump -d build/hello.elf
40080420 <_start>:
40080420:  fff841    l32r    a4, 40080400 <lit_wdt_key> (50d83aa1)   <- line 67
40080423:  050c      movi.n  a5, 0                                   <- line 68
40080425:  fff761    l32r    a6, 40080404 <lit_timg0_wdtwp>          <- line 70
40080428:  0649      s32i.n  a4, a6, 0                               <- line 71
4008042a:  0020c0    memw                                            <- line 72
...
40080448 <next_char>:
40080448:  000232    l8ui    a3, a2, 0                               <- line 88
4008044b:  139c      beqz.n  a3, 40080460 <halt>                     <- line 89
4008044d <wait_for_room>:
4008044d:  0020c0    memw                                            <- line 92
40080450:  0458      l32i.n  a5, a4, 0                               <- line 94
40080452:  755050    extui   a5, a5, 16, 8                           <- line 95
40080455:  f4e5f6    bgeui   a5, 128, 4008044d <wait_for_room>       <- line 96
40080458:  0639      s32i.n  a3, a6, 0                               <- line 98
4008045a:  221b      addi.n  a2, a2, 1                               <- line 102
4008045c:  fffa06    j       40080448 <next_char>                    <- line 103
	...
40080460 <halt>:
40080460:  ffff06    j       40080460 <halt>                         <- line 107
```

* Narrow instructions: for `movi`, `s32i`, `beqz`, `l32i` and `addi` the
  assembler selects the 16-bit `.n` forms where the operands fit
  (Lesson 6.9). Nine of the 25 instructions are narrow: 66 bytes of code
  instead of 75.
* Byte order: objdump prints each instruction as a little-endian number, so
  `fff841` is stored as the bytes `41 f8 ff` (offset `0x7C` in
  `xxd build/hello.bin`).
* The `...` before `halt` is 1 byte of padding. By default the assembler
  keeps an instruction at a branch target from straddling a 4-byte fetch
  boundary; at `0x4008_045F`, the 3-byte `j` at `halt` would straddle one.
  Hence `.text` is 99 bytes; with `xtensa-esp32-elf-as --no-target-align`
  it is 98.

---

## 7.8 Debugging with GDB

QEMU includes a GDB server: `-s` listens on TCP port 1234; `-S` halts the
CPU before the first instruction:

```bash
# terminal 1
qemu-system-xtensa -nographic -machine esp32 \
    -drive file=build/flash.bin,if=mtd,format=raw -s -S

# terminal 2
xtensa-esp32-elf-gdb build/hello.elf
```

```text
(gdb) target remote :1234        # 0x40000400 in ?? ()  <- ROM reset vector
(gdb) break *_start              # Breakpoint 1 at 0x40080420
(gdb) continue                   # ROM runs, loads our image, stops at line 67
(gdb) x/3i $pc                   # disassemble the next 3 instructions
(gdb) break *wait_for_room       # Breakpoint 2 at 0x4008044d (line 92)
(gdb) continue
(gdb) p/c $a3                    # $1 = 72 'H'
(gdb) continue                   # (one more trip round the loop)
(gdb) p/c $a3                    # $2 = 101 'e'
(gdb) p/x $a2                    # $3 = 0x3fff0001   = &message[1]
(gdb) stepi                      # execute one instruction (memw)
(gdb) x/i $pc                    # => 0x40080450: l32i.n a5, a4, 0  (line 94)
(gdb) info registers
```

In `break *label`, `*` denotes the exact address. Without it, GDB treats the
label as a function and may place the breakpoint after the presumed
prologue.

Comments show output from a reference session. The initial PC,
`0x40000400`, is the mask ROM's reset vector.

## 7.9 Not covered (yet)

* Set up a stack or a C runtime (`.bss` zeroing, `.data` copy).
* Write subroutines: the program makes no calls (Lesson 6.7).
* Install exception/interrupt vectors (`VECBASE`).
* Configure the PLL for 160/240 MHz.
* Start APP_CPU.
* Map flash through the MMU (execute-in-place).

Each is an exercise in [Lesson 8](08-exercises.md).
