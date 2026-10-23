# References

Downloaded on 2026-10-23 into `docs/references/`. The files are not committed
(see `.gitignore`): they are third-party copyrighted material, ~43 MB.
Re-download them from the URLs below; the SHA-256 sums identify the revision.

## ESP32 hardware

| File | Source | Use |
|---|---|---|
| `esp32_technical_reference_manual_en.pdf` | <https://www.espressif.com/sites/default/files/documentation/esp32_technical_reference_manual_en.pdf> | Primary reference: memory map, every peripheral register (UART, TIMG, RTC_CNTL...) |
| `esp32_datasheet_en.pdf` | <https://www.espressif.com/sites/default/files/documentation/esp32_datasheet_en.pdf> | Pinout, strapping pins, electrical specs, memory sizes |
| `esp32_errata_en.pdf` | <https://docs.espressif.com/projects/esp-chip-errata/en/latest/esp32/esp-chip-errata-en-master-esp32.pdf> | Silicon bugs (e.g. DPORT/FIFO write issue) |

## CPU / instruction set

| File | Source | Use |
|---|---|---|
| `xtensa_isa_reference_manual.pdf` | <https://0x04.net/~mwk/doc/xtensa.pdf> (Tensilica *Xtensa ISA Reference Manual*, 2010, 662 pages; unofficial mirror) | Primary ISA reference: every instruction's encoding and semantics, options, special registers, memory ordering (section 3.8.3, cited for `memw` in Lesson 7) |
| `xtensa_isa_overview_espressif.pdf` | <https://github.com/espressif/xtensa-isa-doc/releases/download/latest/Xtensa.pdf> (Espressif's *Overview of Xtensa ISA*, 27 pages) | Short introduction: registers, windowed ABI, instruction tables |
| `gnu_as_manual.pdf` | <https://sourceware.org/binutils/docs/as.pdf> | GNU as, including chapter "Xtensa Dependent Features": syntax, literals, relaxation, `--no-target-align` |
| `gnu_ld_manual.pdf` | <https://sourceware.org/binutils/docs/ld.pdf> | GNU ld, including chapter 3 "Linker Scripts" (`ENTRY`, `SECTIONS`) |
| `elf_spec_tis_1.2.pdf` | <https://www.cs.cmu.edu/afs/cs/academic/class/15213-f00/docs/elf.pdf> (TIS ELF 1.2) | ELF headers parsed by `mkimage.py` |

Cadence (which acquired Tensilica) no longer publishes the full ISA manual;
its ISA summary
(<https://www.cadence.com/content/dam/cadence-www/global/en_US/documents/tools/silicon-solutions/compute-ip/isa-summary.pdf>)
blocks scripted downloads (HTTP 403). The 2010 manual covers the ESP32's LX6
core. The binutils manuals track the latest binutils (2.47 at download time),
not the installed 2.43.1; `xtensa-esp32-elf-as --help` lists the exact
options of the installed assembler.

## Boot, image format, tooling

| File | Source |
|---|---|
| `esptool_firmware_image_format.html` | <https://docs.espressif.com/projects/esptool/en/latest/esp32/advanced-topics/firmware-image-format.html> |
| `esptool_boot_mode_selection.html` | <https://docs.espressif.com/projects/esptool/en/latest/esp32/advanced-topics/boot-mode-selection.html> |
| `espidf_v5.5_startup_flow.html` | <https://docs.espressif.com/projects/esp-idf/en/v5.5.6/esp32/api-guides/startup.html> |
| `espidf_v5.5_qemu.html` | <https://docs.espressif.com/projects/esp-idf/en/v5.5.6/esp32/api-guides/tools/qemu.html> |
| `espressif_qemu_esp32_readme.md` | <https://github.com/espressif/esp-toolchain-docs/blob/main/qemu/esp32/README.md> |

## FreeRTOS

| File | Source |
|---|---|
| `freertos_kernel_book_v1.1.0.pdf` | <https://github.com/FreeRTOS/FreeRTOS-Kernel-Book/releases/tag/V1.1.0> (*Mastering the FreeRTOS Real Time Kernel*) |
| `espidf_v5.5_freertos.html` | <https://docs.espressif.com/projects/esp-idf/en/v5.5.6/esp32/api-reference/system/freertos_idf.html> |

## NASM

| File | Source |
|---|---|
| `nasm_manual.pdf` | <https://www.nasm.us/xdoc/2.15.05/nasmdoc.pdf> (matches installed NASM 2.15.05) |

## Source code as documentation

Header files in the local ESP-IDF clone are often the fastest reference:

| Path (under `~/esp/esp-idf/`) | Contents |
|---|---|
| `components/soc/esp32/register/soc/*.h` | Register addresses & bit fields (`uart_reg.h`, `timer_group_reg.h`, `rtc_cntl_reg.h`, `soc.h`) |
| `components/bootloader_support/include/esp_app_format.h` | Image header structs |
| `components/bootloader/subproject/main/ld/esp32/bootloader.ld` | RAM regions safe to load from ROM |
| `components/esp_rom/esp32/ld/esp32.rom.ld` | Addresses of ROM functions |
| `components/freertos/` | FreeRTOS kernel + Xtensa port |
| `components/xtensa/` | Xtensa vectors, window handlers (relevant to exercise 11) |

## SHA-256

```text
73987f96b65af151...  elf_spec_tis_1.2.pdf
a7917e6b47528c9d...  esp32_datasheet_en.pdf
a31e6a35d6ebccd5...  esp32_errata_en.pdf
1007b90e6fafc165...  esp32_technical_reference_manual_en.pdf
fd91add662b703cb...  espidf_v5.5_freertos.html
549eef13134447b0...  espidf_v5.5_qemu.html
671ad69654626f8c...  espidf_v5.5_startup_flow.html
735f24f0413edccb...  espressif_qemu_esp32_readme.md
5abb55eaf63a69d3...  esptool_boot_mode_selection.html
487ff667897be494...  esptool_firmware_image_format.html
577ff48cdc02c8bb...  freertos_kernel_book_v1.1.0.pdf
3ca79c3183de3280...  gnu_as_manual.pdf
b9d9e90d3dde5190...  gnu_ld_manual.pdf
f3ae592cf3e2cd0b...  nasm_manual.pdf
cce3a3135f7d66bf...  xtensa_isa_overview_espressif.pdf
52c28fa26c528782...  xtensa_isa_reference_manual.pdf
```

Full hashes: `docs/references/SHA256SUMS` (committed). Verify with
`cd docs/references && sha256sum -c SHA256SUMS`.
