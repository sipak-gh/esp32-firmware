# esp32-firmware: ESP32 & Bare-Metal Assembly 101

A from-scratch, hands-on course on ESP32 firmware at the lowest level.
Prerequisites: some C and basic x86 assembly (e.g. NASM).

Outcomes:

1. A complete ESP32 toolchain and emulator, installed under `$HOME`.
2. A real FreeRTOS firmware booted on an emulated ESP32 in QEMU.
3. A 208-byte bare-metal firmware in Xtensa assembly, booted directly by the
   ESP32 mask ROM. No SDK, C, RTOS or esptool. It prints `Hello, World!` over
   the UART.
4. A custom firmware-image packer, verified byte-for-byte against
   Espressif's tool.

> **About NASM:** NASM assembles only x86 code; the ESP32 CPU is a Cadence
> **Xtensa LX6**. The course uses the GNU Xtensa assembler, taking only the
> assembler and linker from the vendor toolchain. NASM is installed and
> compared side by side in [Lesson 2](docs/02-why-not-nasm.md).

---

## Course index

| # | Document | Topics |
|---|---|---|
| 1 | [Toolchain Setup: installed tools & dependencies](docs/01-toolchain-setup.md) | Every tool and library: version and role |
| 2 | [Why Not NASM?](docs/02-why-not-nasm.md) | ISAs vs assemblers; x86 vs Xtensa encoding |
| 3 | [ESP32 Architecture](docs/03-esp32-architecture.md) | Cores, memory map, IRAM/DRAM, MMIO, UART & watchdog registers |
| 4 | [Boot Process & Image Format](docs/04-esp32-boot-and-image-format.md) | ROM -> bootloader -> app; the image format byte by byte |
| 5 | [Lab 1: FreeRTOS on QEMU](docs/05-lab1-freertos-on-qemu.md) | Minimal FreeRTOS task demo (ESP-IDF), line by line; booting it in QEMU |
| 6 | [Xtensa Assembly Primer](docs/06-xtensa-assembly-primer.md) | Registers, `l32r` literals, branches, CALL0 vs windowed ABI |
| 7 | [Lab 2: Bare-Metal Hello World](docs/07-lab2-bare-metal-hello-world.md) | Line-by-line walkthrough of all four POC files, machine code, GDB |
| 8 | [Exercises](docs/08-exercises.md) | Warm-ups to projects (C runtime, vectors, real hardware, NASM byte-emitter) |
| - | [References](docs/09-references.md) | Downloaded datasheets, TRM, ISA manual, specs (with URLs & SHA-256) |
| - | [Glossary](docs/glossary.md) | Terms used throughout the course |

The lessons are sequential; each links to the next.

---

## Repository layout

```
esp32-firmware/
+-- README.md                     <- you are here (course index)
+-- docs/                         <- all lessons
|   +-- 01-toolchain-setup.md ... 08-exercises.md
|   +-- 09-references.md, glossary.md
|   +-- references/               <- downloaded PDFs/HTML (git-ignored; SHA256SUMS kept)
+-- freertos-hello/               <- Lab 1: minimal FreeRTOS task demo (ESP-IDF)
|   +-- CMakeLists.txt            <- project definition
|   +-- main/
|       +-- CMakeLists.txt        <- registers the "main" component
|       +-- main.c                <- creates one task that prints every second
+-- hello-asm/                    <- Lab 2: bare-metal Xtensa assembly POC
    +-- src/hello.s               <- the firmware (25 instructions)
    +-- link.ld                   <- memory placement
    +-- tools/mkimage.py          <- ELF -> ESP32 image (+ 4 MB flash image)
    +-- Makefile                  <- make / make run / make clean
```

Every source file is commented line by line; the lessons quote the code with
its actual line numbers. Code changes require matching lesson updates.

---

## Quick start (after completing Lesson 1)

```bash
# Activate the environment (every new terminal; order matters, see Lesson 1.7)
L=~/opt/qemu-libs/usr/lib/x86_64-linux-gnu
export LD_LIBRARY_PATH=$L:$L/pulseaudio
export PATH=~/opt/make/usr/bin:~/opt/nasm/usr/bin:$PATH
export PATH=~/.local/share/uv/python/cpython-3.12-linux-x86_64-gnu/bin:$PATH
. ~/esp/esp-idf/export.sh

# Lab 1 - FreeRTOS on QEMU
cd ~/esp32-firmware/freertos-hello
idf.py set-target esp32 && idf.py build
idf.py qemu                               # quit: Ctrl-A then X

# Lab 2 - bare-metal assembly
cd ~/esp32-firmware/hello-asm
make run                                  # quit: Ctrl-A then X
```

Expected Lab 1 output after the boot log (one line per second; the `I (...)`
timestamp varies between runs):

```text
Hello from a FreeRTOS task! tick=0
I (1834) main_task: Returned from app_main()
Hello from a FreeRTOS task! tick=100
Hello from a FreeRTOS task! tick=200
```

Expected Lab 2 output:

```text
ets Jul 29 2019 12:21:46
rst:0x1 (POWERON_RESET),boot:0x12 (SPI_FAST_FLASH_BOOT)
...
load:0x3fff0000,len:52
load:0x40080400,len:100
entry 0x40080420
Hello, World! (from bare-metal Xtensa assembly)
```

---

## Installed tools & dependencies (summary)

Details, rationale and install steps: [Lesson 1](docs/01-toolchain-setup.md).

| Tool | Version | Location |
|---|---|---|
| uv | 0.13.5 | `~/.local/bin/uv` |
| CPython (via uv) | 3.12.15 | `~/.local/share/uv/python/cpython-3.12-linux-x86_64-gnu/` |
| ESP-IDF (includes FreeRTOS) | v5.5.6 | `~/esp/esp-idf` |
| ESP-IDF Python env (esptool 4.12.0, ...) | Python 3.12 | `~/.espressif/python_env/idf5.5_py3.12_env` |
| xtensa-esp-elf GCC / binutils | 14.2.0 / 2.43.1 (`esp-14.2.0_20260121`) | `~/.espressif/tools/xtensa-esp-elf/` |
| xtensa-esp-elf-gdb | 17.1_20260402 | `~/.espressif/tools/xtensa-esp-elf-gdb/` |
| QEMU (Espressif fork) | 9.2.2 `esp_develop_9.2.2_20260417` | `~/.espressif/tools/qemu-xtensa/` |
| QEMU runtime libs (SDL2, slirp, audio...) | Ubuntu 22.04 `.deb`s | `~/opt/qemu-libs/` |
| CMake / Ninja | 3.30.2 / 1.12.1 | `~/.espressif/tools/{cmake,ninja}/` |
| GNU Make | 4.3 | `~/opt/make/` |
| NASM | 2.15.05 | `~/opt/nasm/` |
| Also installed by ESP-IDF (unused here) | openocd-esp32 v0.12.0-esp32-20260831, esp32ulp-elf 2.38_20240113 | `~/.espressif/tools/` |
| pypdf (optional, for searching the reference PDFs) | 6.21.2, run via `uv run --with pypdf` | `~/.cache/uv/` |

Host: Ubuntu 22.04.5 LTS x86_64; tools are installed under `$HOME`.
