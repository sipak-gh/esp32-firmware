# Lesson 3: ESP32 Architecture for Firmware Writers

> **Goal:** a model of the chip (CPUs, memory map, buses, peripherals)
> detailed enough to write code without an SDK.
>
> Primary source: *ESP32 Technical Reference Manual* (TRM), chapters
> "System and Memory", "UART", "Timer Group", "RTC/Low-Power Management".
> Local copy: `docs/references/esp32_technical_reference_manual_en.pdf`.

## 3.1 The chip at a glance

| Feature | ESP32 (original) |
|---|---|
| CPU cores | 2 x Cadence Xtensa LX6, 32-bit, up to 240 MHz |
| Core names | **PRO_CPU** (core 0) and **APP_CPU** (core 1) |
| Endianness | Little-endian |
| On-chip ROM | 448 KB (boot loader, libc helpers, `ets_printf`, ...) |
| On-chip SRAM | 520 KB (SRAM0 192 KB + SRAM1 128 KB + SRAM2 200 KB) |
| RTC memory | 8 KB RTC FAST + 8 KB RTC SLOW (survive deep sleep) |
| Flash | External SPI flash (e.g. 4 MB), mapped into the address space through a cache/MMU |
| Radios | Wi-Fi 802.11 b/g/n, Bluetooth Classic + BLE |

After reset only PRO_CPU runs; APP_CPU stays stalled until software releases
it. The bare-metal POC never wakes it.

## 3.2 Harvard-ish: two buses into the same RAM

The LX6 has separate **instruction** and **data** buses; the ESP32 maps some
RAM onto both, at different addresses. Hence the two address families:
`0x3F...` (data bus) and `0x40...` (instruction bus).

```
0x3F40_0000 +--------------------------+
            | External flash (DROM)    | data bus, read-only, via cache
0x3F80_0000 +--------------------------+
            | External PSRAM           | (if fitted)
0x3FF0_0000 +--------------------------+
            | Peripherals (DPORT bus)  | UART0 = 0x3FF4_0000, RTC_CNTL = 0x3FF4_8000,
            |                          | TIMG0 = 0x3FF5_F000, ...
0x3FF8_0000 +--------------------------+
            | RTC FAST memory (data)   |
0x3FFA_E000 +--------------------------+
            | SRAM2  (DRAM)            | ESP-IDF app data starts at 0x3FFB_0000
0x3FFE_0000 +--------------------------+
            | SRAM1  (DRAM)            | ROM uses parts of this while booting;
            |                          | our .rodata goes to 0x3FFF_0000
0x4000_0000 +--------------------------+
            | Internal ROM (IROM0)     | mask ROM code: reset vector, boot loader
0x4007_0000 +--------------------------+
            | SRAM0  (IRAM)            | 0x4007_0000-0x4007_FFFF: flash cache
            |                          | 0x4008_0000+: free IRAM; our .text at 0x4008_0400
0x400A_0000 +--------------------------+
            | SRAM1 alias (IRAM)       | same physical RAM as 0x3FFE_0000.. (reversed)
0x400C_0000 +--------------------------+
            | RTC FAST (instr)         |
0x400D_0000 +--------------------------+
            | External flash (IROM)    | instruction bus, via cache
0x5000_0000 +--------------------------+
            | RTC SLOW memory          |
0x6000_0000 +--------------------------+
            | Peripherals (AHB view)   | UART0 FIFO also reachable at 0x6000_0000
            +--------------------------+
```

> **Rule:** IRAM (`0x4007_0000-0x400B_FFFF`) supports only aligned 32-bit
> loads and stores. An `l8ui` (load byte) from IRAM raises a `LoadStoreError`
> exception on real silicon, so the POC keeps its string in DRAM. QEMU is more
> permissive and cannot be relied on to catch this.

## 3.3 Memory-mapped I/O

There are no dedicated I/O instructions (cf. x86 `in`/`out`). Each peripheral
is a block of 32-bit **registers** at fixed addresses: writes configure or
send, reads return status.

The three peripherals used by the POC:

| Register | Address | Meaning |
|---|---|---|
| `UART_FIFO_REG(0)` (AHB) | `0x6000_0000` | Write a byte -> queued for transmission on UART0 (GPIO1/TX). |
| `UART_STATUS_REG(0)` | `0x3FF4_001C` | Bits [23:16] `UART_TXFIFO_CNT`: bytes waiting in the 128-byte TX FIFO. |
| `TIMG_WDTCONFIG0_REG(0)` | `0x3FF5_F048` | Timer Group 0 watchdog config (bit 31 = enable). |
| `TIMG_WDTWPROTECT_REG(0)` | `0x3FF5_F064` | Write `0x50D83AA1` to unlock the WDT registers. |
| `RTC_CNTL_WDTCONFIG0_REG` | `0x3FF4_808C` | RTC watchdog config. |
| `RTC_CNTL_WDTWPROTECT_REG` | `0x3FF4_80A4` | Write `0x50D83AA1` to unlock. |

Addresses are from the TRM register chapters and match ESP-IDF's generated
headers (`components/soc/esp32/register/soc/uart_reg.h`, `rtc_cntl_reg.h`,
`timer_group_reg.h`, `soc.h`), a legitimate and fast register reference.
The POC defines them in `hello.s` lines 22-28.

### Why write the UART FIFO via `0x6000_0000`?

Per the ESP32 errata, back-to-back writes to the same peripheral address over
the DPORT bus (`0x3FF4_xxxx`) can be lost. ESP-IDF therefore writes FIFOs
through the AHB alias (`UART_FIFO_AHB_REG`), as does the POC. See
`docs/references/esp32_errata_en.pdf`.

### `memw` - memory barrier

The Xtensa ISA permits a CPU to "perform ordinary load and store operations
in any order" (ISA Reference Manual, Section 3.8.3), provided a program
reading back its own data cannot observe the difference. For peripheral
registers the order of accesses is essential: unlock, then disable a
watchdog; write a byte, then read the FIFO level. `memw` ("memory wait")
guarantees that every load/store before it happens before every load/store
after it. The POC uses it three times (`hello.s` lines 72, 78 and 92; see
Lesson 7.3).

## 3.4 State left by the ROM

State when the ROM jumps to the entry point:

* UART0: initialised at 115200 baud, 8N1 on GPIO1 (TX) / GPIO3 (RX) (the
  ROM prints its `ets Jul 29 2019` banner this way); ready for direct writes.
* CPU clock: still derived from the crystal (typically 40 MHz, no PLL); slow
  but sufficient.
* Watchdogs: in flash-boot mode the ROM arms the RTC WDT and the Timer
  Group 0 WDT; unless disabled or fed, they reset a real chip within a few
  seconds. ESP-IDF's bootloader and the POC disable them first.
* Interrupts: no firmware handlers or vector table are installed. The POC
  never enables interrupts and runs straight-line code.
* Stack: `a1` still holds the ROM's stack. The POC never touches the stack
  (no calls, nothing stored in RAM).

## 3.5 Peripheral registers: a recipe

1. Find the peripheral's base address (TRM "Peripheral address mapping"
   table, or `soc.h`).
2. Find the register offset and bit fields (TRM register description).
3. Check for write protection (WDTs, RTC) and for errata.
4. Load the address into a register (`l32r`), then `l32i`/`s32i`.
5. Put `memw` between accesses whose order matters.

Next: [Lesson 4: Boot Process & Image Format](04-esp32-boot-and-image-format.md)
