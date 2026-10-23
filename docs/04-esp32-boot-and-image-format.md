# Lesson 4: The ESP32 Boot Process & Firmware Image Format

> **Goal:** the sequence from power-on to the first instruction of
> application code, and the byte layout the ROM expects in flash.
>
> Sources: `docs/references/esptool_firmware_image_format.html`,
> `esptool_boot_mode_selection.html`, `espidf_v5.5_startup_flow.html`,
> and ESP-IDF's `components/bootloader_support/include/esp_app_format.h`.

## 4.1 Three stages (normal ESP-IDF firmware)

```
 power-on / reset
       |
       v
+----------------------+  mask ROM @ 0x4000_0000, cannot be changed
| Stage 1: ROM loader  |  - samples strapping pins (boot mode)
|                      |  - inits UART0, SPI flash
|                      |  - reads image at FLASH OFFSET 0x1000
|                      |  - copies its segments into RAM, verifies checksum
+---------+------------+  - jumps to entry point
          v
+----------------------+  ESP-IDF "2nd-stage bootloader" (flash 0x1000)
| Stage 2: bootloader  |  - reads partition table at flash 0x8000
|                      |  - picks app partition (e.g. factory @ 0x10000)
|                      |  - sets up flash MMU/cache, loads RAM segments
+---------+------------+  - jumps to call_start_cpu0
          v
+----------------------+  the ESP-IDF app
| Stage 3: application |  - C runtime init, heap, clocks
|                      |  - starts FreeRTOS scheduler, APP_CPU
|                      |  - calls app_main() in the "main" task
+----------------------+
```

The bare-metal POC replaces stages 2 and 3: the ROM loads the POC image from
0x1000 and jumps directly to its assembly entry point. Nothing else runs.

## 4.2 Reading the ROM's boot log

QEMU output for the POC:

```text
ets Jul 29 2019 12:21:46                          <- ROM build date (ESP32 rev3 ROM)

rst:0x1 (POWERON_RESET),boot:0x12 (SPI_FAST_FLASH_BOOT)
      |                        +- strapping pins value -> boot from SPI flash
      +- reset reason
configsip: 0, SPIWP:0xee                          <- SPI pin config (0xEE = default pins)
clk_drv:0x00,q_drv:0x00,d_drv:0x00,cs0_drv:0x00,hd_drv:0x00,wp_drv:0x00
mode:DIO, clock div:2                             <- flash mode & clock from the image header
load:0x3fff0000,len:52                            <- segment 0 (.rodata -> DRAM)
load:0x40080400,len:100                           <- segment 1 (.text   -> IRAM)
entry 0x40080420                                  <- jumping to _start
Hello, World! (from bare-metal Xtensa assembly)   <- this program
```

### Boot mode and strapping pins

At reset the ROM latches several GPIOs, the **strapping pins**:

| Pin | Effect |
|---|---|
| GPIO0 | 1 (pulled up, default) = boot from flash; 0 = UART **download mode** (used by `esptool` to flash) |
| GPIO2 | Must be low/floating for download mode |
| MTDI (GPIO12) | Flash voltage (3.3 V vs 1.8 V) |
| MTDO (GPIO15) | 0 = silence the ROM boot log on UART0 |
| GPIO5 | SDIO slave timing |

`boot:0x12` (`SPI_FAST_FLASH_BOOT`) is normal boot from flash.

## 4.3 Flash layout used in this course

```
Offset      ESP-IDF FreeRTOS app             Our bare-metal POC
0x0000      (unused, 0xFF)                   (unused, 0xFF)
0x1000      2nd-stage bootloader image       * hello.bin (our whole firmware)
0x8000      partition table
0x9000      nvs partition
0xF000      phy_init partition
0x10000     factory app (freertos_hello)
...
0x3FFFFF    end of 4 MB flash
```

The ROM always starts at offset `0x1000`. Erased NOR flash reads as `0xFF`;
unused space is therefore filled with `0xFF`.

## 4.4 The image format, byte by byte

An ESP32 image consists of a header, a list of segments and a checksum.

### Header (24 bytes)

| Offset | Size | Field | POC value | Notes |
|---|---|---|---|---|
| 0 | 1 | magic | `E9` | any other value is rejected |
| 1 | 1 | segment count | `02` | |
| 2 | 1 | SPI mode | `02` | 0 QIO, 1 QOUT, **2 DIO**, 3 DOUT |
| 3 | 1 | size/freq | `20` | high nibble size (0 1 MB, 1 2 MB, **2 4 MB**, 3 8 MB, 4 16 MB); low nibble freq (**0 40 MHz**, 1 26 MHz, 2 20 MHz, F 80 MHz) |
| 4 | 4 | entry address | `20 04 08 40` -> `0x40080420` | little-endian |
| 8 | 1 | WP pin | `EE` | `0xEE` = not used |
| 9 | 3 | SPI pin drive | `00 00 00` | |
| 12 | 2 | chip ID | `00 00` | 0 = ESP32 |
| 14 | 1 | min chip rev (legacy) | `00` | |
| 15 | 2 | min chip rev (full) | `00 00` | |
| 17 | 2 | max chip rev (full) | `FF FF` | `0xFFFF` = no limit |
| 19 | 4 | reserved | `00...` | |
| 23 | 1 | hash appended | `00` | 1 = SHA-256 of the image follows the checksum |

Bytes 8-23 form the *extended header*; the legacy ESP8266 format had only
the first 8 bytes.

### Segments (repeated `segment count` times)

| Size | Field |
|---|---|
| 4 | load address (copy destination in RAM) |
| 4 | length in bytes (multiple of 4) |
| *length* | data |

### Footer

1. Zero padding until `(file length + 1) % 16 == 0`.
2. One **checksum** byte: `0xEF` XOR all segment *data* bytes (segment
   headers excluded).
3. Optional 32-byte SHA-256, present only if `hash appended = 1`.

### The POC image, annotated

All 208 bytes of `hello-asm/build/hello.bin`. `xxd` prints 16 bytes per
row; bars mark field boundaries.

```text
$ xxd hello-asm/build/hello.bin
00000000: e902 0220 2004 0840 ee00 0000 0000 0000
00000010: 00ff ff00 0000 0000 | 0000 ff3f 3400 0000
00000020: 4865 6c6c 6f2c 2057 6f72 6c64 2120 2866   Hello, World! (f
00000030: 726f 6d20 6261 7265 2d6d 6574 616c 2058   rom bare-metal X
00000040: 7465 6e73 6120 6173 7365 6d62 6c79 290d   tensa assembly).
00000050: 0a00 0000 | 0004 0840 6400 0000 | a13a d850
00000060: 64f0 f53f 48f0 f53f a480 f43f 8c80 f43f
00000070: 0000 ff3f 1c00 f43f 0000 0060 | 41f8 ff0c
00000080: 0561 f7ff 4906 c020 0061 f6ff 5906 61f6
  ...
000000b0: 75f6 e5f4 3906 1b22 06fa ff00 06ff ff | 00
000000c0: 0000 0000 0000 0000 0000 0000 0000 00 | 05
```

| Offset | Bytes | Meaning | Produced by |
|---|---|---|---|
| `0x00` | `e9 02 02 20` | magic, 2 segments, DIO, 4 MB @ 40 MHz | `mkimage.py` lines 42-46 |
| `0x04` | `20 04 08 40` | entry = `0x4008_0420` (`_start`) | line 47, from `link.ld` line 10 |
| `0x08` | `ee 00 00 00 00 00 00 00 00 ff ff 00 00 00 00 00` | WP pin, drive, chip ID 0, revisions, max rev `FFFF`, reserved, no hash | lines 48-55 |
| `0x18` | `00 00 ff 3f` `34 00 00 00` | segment 0: address `0x3FFF_0000`, length `0x34` = 52 | line 65 |
| `0x20` | `48 65 6c ...` `0d 0a 00` + `00 00` | 50-byte string (`hello.s` line 38) + 2 padding bytes | line 64 |
| `0x54` | `00 04 08 40` `64 00 00 00` | segment 1: address `0x4008_0400`, length `0x64` = 100 | line 65 |
| `0x5C` | `a1 3a d8 50` `64 f0 f5 3f` ... `00 00 00 60` | literal pool, 8 words (`hello.s` lines 50-57) | `as`/`ld` |
| `0x7C` | `41 f8 ff 0c 05 ...` | code, starting with `l32r a4, lit_wdt_key` (`hello.s` line 67) | `as`/`ld` |
| `0xBC` | `06 ff ff` | `j halt` (`hello.s` line 107), last instruction | `as` |
| `0xBF` | `00` | 1 byte of segment padding (99 -> 100) | line 64 |
| `0xC0` | `00` x 15 | padding; places the checksum in the last byte of a 16-byte row | line 71 |
| `0xCF` | `05` | checksum | line 72 |

Last-column line numbers refer to `hello-asm/tools/mkimage.py` unless
stated otherwise; [Lesson 7](07-lab2-bare-metal-hello-world.md#75-toolsmkimagepy)
covers that file.

`esptool.py --chip esp32 image_info --version 2 build/hello.bin` decodes the
same fields and reports `Checksum: 0x5 (valid)`. `mkimage.py` output is
byte-for-byte identical to `esptool.py elf2image --dont-append-digest`.

## 4.5 Rules the ROM imposes on segments

* Load addresses must lie in RAM unused by the ROM during loading. The ROM
  keeps its stack and data in parts of SRAM1; the POC therefore reuses the
  regions of the ESP-IDF bootloader (`bootloader.ld`): IRAM `0x4008_0400...`
  and DRAM `0x3FFF_0000...` (24 KB).
* The ROM only copies into RAM; it does not configure the flash cache/MMU.
  Execute-in-place from flash (`0x400D_xxxx`) is possible only after stage 2
  configures the MMU.
* Data lengths are padded to 4 bytes.
* `entry` must point at valid Xtensa code inside a loaded IRAM segment.

Next: [Lesson 5: Lab 1, FreeRTOS on QEMU](05-lab1-freertos-on-qemu.md)
