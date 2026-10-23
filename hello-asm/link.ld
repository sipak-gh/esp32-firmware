/* link.ld - tell the linker where the program lives in ESP32 memory.
 *
 * The ROM copies each loadable part of our image to the address chosen here,
 * so these must be RAM regions that the ROM is not using while it loads us.
 * ESP-IDF's own bootloader loads to the same two regions
 * (components/bootloader/subproject/main/ld/esp32/bootloader.ld).
 */

/* Record _start in the ELF header as the entry point. */
ENTRY(_start)

SECTIONS
{
    /* Code (and its literal pool) -> internal instruction RAM (IRAM). */
    .text   0x40080400 : { *(.text) }

    /* The message string -> internal data RAM (DRAM). */
    .rodata 0x3FFF0000 : { *(.rodata) }
}
