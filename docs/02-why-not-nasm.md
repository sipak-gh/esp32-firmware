# Lesson 2: Why Not NASM? (Assemblers vs. Instruction Sets)

> **Goal:** explain why an assembler is tied to one CPU architecture and why
> this course uses the GNU Xtensa assembler rather than NASM.

## 2.1 What an assembler actually does

An assembler translates mnemonics into the bit patterns a specific CPU
decodes. That mapping is the **Instruction Set Architecture (ISA)**; each CPU
family has its own:

| CPU | ISA | Examples |
|---|---|---|
| PC | x86 / x86-64 (CISC, 1-15-byte instructions) | Intel Core, AMD Ryzen |
| ESP32, ESP32-S2, ESP32-S3 | Xtensa LX6 / LX7 (RISC, 16- or 24-bit instructions) | this course |
| ESP32-C3, C6, H2, P4 | RISC-V (RV32IMC...) | |
| Raspberry Pi, phones | ARM / AArch64 | |

**NASM** (the Netwide Assembler) targets x86 only, as its output formats
show:

```text
$ nasm -hf
    -f format     select output file format
       bin      Flat raw binary (MS-DOS, embedded, ...) [default]
       elf32    ELF32 (i386) (Linux, most Unix variants)
       elf64    ELF64 (x86-64) (Linux, most Unix variants)
       win32    Microsoft extended COFF for Win32 (i386)
       macho32  Mach-O i386 ...
```

Every format is i386 or x86-64; none is Xtensa, ARM or RISC-V.

## 2.2 Try it yourself

One operation on both architectures: load the address `0x60000000` into a
register, then store a byte there.

**x86 with NASM**

```nasm
bits 32
mov eax, 0x60000000      ; B8 00 00 00 60
mov byte [eax], 0x48     ; C6 00 48
```

```text
$ nasm -f bin -o x.bin x.asm && xxd x.bin
00000000: b800 0000 60c6 0048                      ....`..H
```

x86 embeds the full 32-bit constant in the instruction (5 bytes for the
`mov`).

**Xtensa with GNU as** (excerpts from `hello-asm/src/hello.s`; see
[Lesson 6](06-xtensa-assembly-primer.md))

```asm
lit_uart_fifo:      .word UART0_FIFO     # line 57: 0x60000000, stored in memory
...
    l32r    a6, lit_uart_fifo            # line 85: fff561 (24-bit instruction)
...
    s32i    a3, a6, 0                    # line 98: 0639   (16-bit "density" form)
```

Xtensa instructions are 16 or 24 bits wide and cannot hold a 32-bit
constant, so it is stored in a **literal pool** and loaded PC-relative with
`l32r`.

NASM does not recognise Xtensa mnemonics:

```text
$ printf 'bits 32\nmovi a2, 1\n' > y.asm && nasm -f bin y.asm
y.asm:2: error: parser: instruction expected
```

## 2.3 "Could NASM emit the bytes anyway?"

In principle, yes. `-f bin` with `db`/`dw`/`dd` writes arbitrary bytes, and
NASM macros could hand-encode Xtensa instructions (`movi a5, 0` is the three
bytes `52 a0 00`). NASM then serves only as a byte emitter; the assembler
itself must be re-implemented. This is an advanced exercise (see
[Exercises](08-exercises.md)), not a practical way to learn.

## 2.4 The alternative: GNU as

| Job | Tool | Notes |
|---|---|---|
| Assemble `.s` -> `.o` | `xtensa-esp32-elf-as` (GNU binutils 2.43.1) | Knows the ESP32's exact Xtensa configuration. |
| Link `.o` -> `.elf` | `xtensa-esp32-elf-ld` + the course's `link.ld` | Places code/data at real ESP32 addresses. |
| Inspect | `xtensa-esp32-elf-objdump -d`, `xtensa-esp32-elf-readelf -l` | |
| `.elf` -> bootable `.bin` | `hello-asm/tools/mkimage.py` (course-written) | Replaces `esptool elf2image`; 83 lines of standard-library Python. |
| Run | `qemu-system-xtensa -machine esp32` | |

The firmware contains no ESP-IDF code, C or libraries. Only the assembler
and linker are borrowed, as NASM + `ld` would be on x86.

> **"esp32" in the tool name.** Xtensa is a configurable ISA: each chip vendor
> selects options (density instructions, MAC16, windowed registers, FPU,
> number of registers...). `xtensa-esp32-elf-as` is preconfigured for the
> ESP32's choices, `xtensa-esp32s3-elf-as` for the S3's.

## 2.5 Using NASM anyway

NASM suits real-mode/protected-mode x86 bare metal, e.g. a 512-byte PC boot
sector printing via BIOS `int 0x10` under `qemu-system-x86_64`. The concepts
(reset vector, memory map, linker placement, UART access through registers)
transfer directly to this course.

Next: [Lesson 3: ESP32 Architecture](03-esp32-architecture.md)
