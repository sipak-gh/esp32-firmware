# Glossary

| Term | Meaning |
|---|---|
| **AHB** | On-chip bus. The ESP32 exposes some peripheral FIFOs at `0x6000_xxxx` via AHB. |
| **APP_CPU / PRO_CPU** | The ESP32's two Xtensa cores (core 1 / core 0). Only PRO_CPU runs after reset. |
| **Bare metal** | Code that runs directly on hardware with no OS or SDK underneath. |
| **Bootloader (2nd stage)** | ESP-IDF program at flash `0x1000` that loads the application; replaced by the POC. |
| **CALL0 ABI** | Non-windowed Xtensa calling convention: `call0`/`ret`, return address in `a0`. |
| **Checksum (image)** | `0xEF` XOR all segment data bytes; last byte of the padded image. |
| **Cross toolchain** | Compiler/assembler/linker that runs on one architecture (x86-64) and targets another (Xtensa). |
| **Density option** | Xtensa feature that adds 16-bit "narrow" encodings (`.n` suffix). |
| **DPORT** | The ESP32's main peripheral bus window (`0x3FF0_0000-0x3FF7_FFFF`). |
| **DRAM / IRAM** | Same SRAM seen via the data bus (`0x3FF...`) or the instruction bus (`0x400...`). IRAM: 32-bit accesses only. |
| **DROM / IROM** | External flash mapped (via cache/MMU) on the data / instruction bus. |
| **ELF** | Executable and Linkable Format: the linker's output, with sections, segments and symbols. |
| **Entry point** | Address of the first instruction executed in the image (`_start`). |
| **ESP-IDF** | Espressif IoT Development Framework, the official SDK (includes FreeRTOS). |
| **esptool** | Espressif's Python tool for flashing chips and converting ELF -> image. |
| **FreeRTOS** | Small real-time OS kernel: tasks, scheduler, queues, semaphores. |
| **ISA** | Instruction Set Architecture: the contract between machine code and the CPU. |
| **Linker script** | File (`link.ld`) specifying where `ld` places sections in memory. |
| **Literal pool** | 32-bit constants stored in memory near the code, loaded with `l32r`. |
| **`memw`** | Xtensa memory barrier; orders loads and stores. |
| **MMIO** | Memory-mapped I/O: peripherals controlled by reads/writes to addresses. |
| **NASM** | Netwide Assembler, x86/x86-64 only. |
| **Polling** | Repeatedly reading a status register until the hardware is ready. |
| **QEMU** | Machine emulator. Espressif's fork adds `-machine esp32`. |
| **ROM bootloader** | Code in on-chip mask ROM that runs at reset and loads the image from flash `0x1000`. |
| **Segment (image)** | `(load address, length, data)` block the ROM copies to RAM. |
| **Strapping pins** | GPIOs sampled at reset to choose boot mode, flash voltage, etc. |
| **UART** | Serial port. UART0 on GPIO1/3 is the ESP32 console, 115200 baud. |
| **Watchdog (WDT)** | Timer that resets the chip unless periodically fed or disabled. |
| **Windowed ABI** | Xtensa calling convention using `call4/8/12`, `entry`, `retw`; rotates the register window; requires exception handlers. |
| **Xtensa LX6** | Cadence/Tensilica configurable 32-bit RISC CPU core used in the ESP32. |
