# Lesson 6: Xtensa Assembly Primer (for people who know a little x86/NASM)

> **Goal:** the subset of Xtensa LX6 assembly (registers, instruction
> formats, constants, memory access, branches, calls) needed to read and
> write the POC.
>
> Sources: `docs/references/xtensa_isa_reference_manual.pdf` (full ISA
> manual), `docs/references/gnu_as_manual.pdf` (chapter "Xtensa Dependent
> Features").

## 6.1 Big picture

| | x86 (NASM) | Xtensa LX6 (GNU as) |
|---|---|---|
| Design | CISC | RISC, load/store |
| Instruction size | 1-15 bytes | 24-bit, or 16-bit "narrow" (`.n`) with the Density option |
| General registers | `eax`, `ebx`, ... (8 in 32-bit mode) | `a0`-`a15` (16 visible; ESP32 has 64 physical, windowed) |
| Memory operands in ALU ops | yes (`add eax, [ebx]`) | no; only `l*`/`s*` access memory |
| 32-bit immediate | `mov eax, 0x12345678` | no; literal pool + `l32r` |
| Syntax | `mov dst, src` | `op dst, src1, src2` (`add a2, a3, a4`: a2 = a3 + a4) |
| Comments | `;` | `#` to end of line (as in `hello.s`); `/* ... */` and `//` also accepted |
| Flags register | `EFLAGS` | none; branches compare registers directly |

## 6.2 Registers

**Address registers** (AR) `a0`-`a15`. Two have conventional roles:

| Reg | Role |
|---|---|
| `a0` | return address (written by `call0`/`callN`) |
| `a1` | stack pointer (`sp`) |
| `a2`-`a7` | arguments; `a2` (and `a3`...) return values (CALL0 ABI) |
| `a12`-`a15` | callee-saved (CALL0 ABI) |

**Special registers** (SR) are read and written with `rsr`, `wsr` and `xsr`:
`PS` (processor state, interrupt level), `SAR` (shift amount), `EPC1`/`EXCCAUSE`
(exception info), `VECBASE` (vector table base), `CCOUNT` (cycle counter),
`LBEG`/`LEND`/`LCOUNT` (zero-overhead loops), `WINDOWBASE`/`WINDOWSTART`.

```asm
rsr.ccount  a2          /* a2 = CPU cycle counter (handy for delays) */
```

The PC is not a general register; jumps, branches and calls change it.

## 6.3 Constants: `movi` vs `l32r`

```asm
movi  a5, 0             /* 12-bit signed immediate: -2048..2047 */
movi  a5, 1000          /* fine */
```

Larger values, including all peripheral addresses, must be loaded from
memory:

```asm
    .align 4
lit_uart_status: .word 0x3FF4001C     /* literal pool entry */
    ...
    l32r  a4, lit_uart_status          /* a4 = *(PC-relative literal) */
```

`hello.s` uses this pattern: pool at lines 45-57, `l32r`s at
lines 67-85 (Lesson 7.3).

`l32r` encodes a 16-bit negative word offset: the literal must precede the
instruction, within 256 KB. GNU as can also manage pools:
`movi a4, 0x3FF4001C` is assembled as an `l32r` plus a literal placed in a
separate `.literal` section (or, with `--text-section-literals`, at the
previous `.literal_position` directive). The linker script must then place
`.literal` before `.text`. A hand-written pool makes the mechanism explicit
and keeps `link.ld` minimal.

## 6.4 Loads and stores

Form: `op  reg, base, offset`; address = `base + offset` (offset unsigned,
scaled).

| Instr | Meaning | Offset range |
|---|---|---|
| `l8ui a3, a2, 0` | a3 = zero-extended byte at a2+0 | 0..255 |
| `l16ui` / `l16si` | 16-bit unsigned / signed | 0..510, step 2 |
| `l32i a5, a4, 0` | 32-bit word | 0..1020, step 4 |
| `s8i` / `s16i` / `s32i` | stores | same as loads |

Accesses must be naturally aligned. IRAM allows only 32-bit accesses
(Lesson 3).

## 6.5 Arithmetic & bit manipulation (selection)

```asm
add   a2, a3, a4        /* a2 = a3 + a4 */
addi  a2, a2, 1         /* immediate -128..127 */
sub   a2, a3, a4
and   a2, a3, a4  /  or  /  xor
slli  a2, a3, 4         /* shift left logical by 4 */
srli  a2, a3, 4         /* shift right logical (0..15; use extui/ssr+srl for more) */
extui a5, a5, 16, 8     /* a5 = (a5 >> 16) & 0xFF  - extract a bit field */
```

`extui` (extract unsigned immediate) suits register bit fields such as
`UART_TXFIFO_CNT` (bits [23:16]).

## 6.6 Branches: compare-and-branch, no flags

```asm
beqz  a3, done          /* if a3 == 0 goto done   (12-bit range) */
bnez  a3, loop
beq   a2, a3, label     /* register vs register   (8-bit range)  */
bltu  a2, a3, label     /* unsigned <              */
bgeui a5, 128, label    /* register vs immediate   */
bbsi  a2, 31, label     /* branch if bit 31 of a2 set */
j     label             /* unconditional, +/-128 KB  */
```

> **Pitfall:** `beqi/bnei/blti/bgei` and `bltui/bgeui` do not accept
> arbitrary immediates. Only values from a fixed table fit in the 4-bit
> field:
>
> * `b4const` (signed): -1, 1, 2, 3, 4, 5, 6, 7, 8, 10, 12, 16, 32, 64, 128, 256
> * `b4constu` (unsigned): 32768, 65536, 2, 3, 4, 5, 6, 7, 8, 10, 12, 16, 32, 64, 128, 256
>
> `bgeui a5, 126, ...` fails with *operand 2 of 'bgeui' has invalid value
> '126'*. Use a table value (`hello.s` line 96 uses 128) or load the
> constant into a register and use `bgeu`.

## 6.7 Calling conventions: CALL0 vs windowed

The POC makes no calls; the print loop is inline. For subroutines, Xtensa
supports two ABIs.

**CALL0 ABI**, classic RISC style:

```asm
    call0 uart_putc     /* a0 = return address; jump */
    ...
uart_putc:
    ...
    ret                 /* jump to a0 */
```

A routine that calls another routine must first save `a0`, usually on the
stack (which the POC does not set up). Lesson 8, exercise 5: write
`uart_putc` this way.

**Windowed ABI** (ESP-IDF/GCC default): `call4`/`call8`/`call12` rotate the
register window by 4/8/12 registers, giving the callee fresh `a0`-`a15`
without saves. The callee begins with `entry a1, <frame>` and returns with
`retw`. When the 64 physical registers are exhausted, the CPU raises
**window overflow/underflow exceptions**, whose handlers spill registers to
the stack. These handlers reside in the exception vector table, which the
POC does not install. Bare-metal code without vectors must therefore use
CALL0 or, like the POC, make no calls. Setting up `VECBASE` and the window
handlers is a follow-up project (Lesson 8, exercise 11).

## 6.8 Other common instructions

| Instr | Purpose |
|---|---|
| `memw` | memory barrier: all loads/stores before it are ordered before all loads/stores after it; required between device-register accesses whose order matters (ISA RM section 3.8.3; `hello.s` lines 72, 78, 92) |
| `isync`, `dsync`, `rsync`, `esync` | pipeline syncs after special-register writes |
| `nop` | no operation |
| `waiti 0` | sleep until an interrupt (low-power idle) |
| `loop a2, end` | zero-overhead loop; executes the block `a2` times |
| `mull`, `quou`, `remu` | multiply / divide (ESP32 has the MUL32 and DIV32 options) |

## 6.9 Narrow (density) instructions

The Density option provides 16-bit forms of many common instructions:
`mov.n`, `addi.n`, `l32i.n`, `s32i.n`, `beqz.n`, `ret.n`, ... GNU as selects
the narrow form automatically when the operands fit. The disassembly in
Lesson 7.7 therefore shows `movi.n`, `s32i.n`, `l32i.n`, `beqz.n` and
`addi.n` where the source has `movi`, `s32i`, `l32i`, `beqz` and `addi`:
smaller code, identical semantics.

## 6.10 GNU as directives used in this course

| Directive | Meaning | NASM equivalent |
|---|---|---|
| `.section .text` | switch section | `section .text` |
| `.global _start` | export symbol | `global _start` |
| `.align 4` | align to 4 bytes | `align 4` |
| `.word 0x1234` | 32-bit value | `dd 0x1234` |
| `.asciz "hi"` | string + NUL | `db "hi", 0` |
| `.set NAME, value` | assemble-time constant | `NAME equ value` |
| `label:` | label | `label:` |

File extensions: by convention `.s` (lower case, as in `hello.s`) is plain
assembly passed directly to `as`; `.S` (upper case) is first run through
the C preprocessor by `gcc`, so `#define` and `#include` work.

Next: [Lesson 7: Lab 2, Bare-Metal Hello World](07-lab2-bare-metal-hello-world.md)
