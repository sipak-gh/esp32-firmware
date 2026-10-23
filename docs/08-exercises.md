# Lesson 8: Exercises

Ordered roughly from warm-up (`*`) to project-sized (`****`). All exercises
build on `hello-asm/`; copy it first: `cp -r hello-asm my-exercise`.

## Warm-up

1. `*` **Change the message.** Rebuild and check the new segment length in
   the ROM's `load:` line (or with `xtensa-esp32-elf-readelf -l build/hello.elf`).
   Why is the length rounded up to a multiple of 4?
2. `*` **Break the checksum.** Flip one byte in `build/hello.bin`, rebuild
   `flash.bin` around it (or hex-edit `flash.bin` at `0x1000+N`), and boot.
   What does the ROM print? Compare with `esptool.py image_info`.
3. `*` **Break the magic.** Change `0xE9` in `mkimage.py`. How does the ROM
   handle an invalid image?
4. `*` **Move the string into IRAM** (place `message` in `.text`). Does it
   still work in QEMU? Explain why it would crash on silicon (Lesson 3.2).

## Core

5. `**` **Subroutines.** Move the "wait for room, then write" part of the
   loop (`hello.s` lines 91-98) into a CALL0 routine `uart_putc` (`call0` /
   `ret`, character in `a2`, Lesson 6.7). Then write `uart_puthex`, which
   prints a register as 8 hex digits via `uart_putc`, and use it to print
   the `CCOUNT` register (`rsr.ccount`). `uart_puthex` must save `a0` before
   any call; where can it do so without a stack?
6. `**` **Delay loop.** Print a line once per second using `CCOUNT`. Right
   after ROM boot the CPU runs at the crystal frequency; measure it.
7. `**` **Echo.** Read characters from UART0 (RX FIFO count:
   `UART_STATUS_REG` bits [7:0]; read bytes from the FIFO register) and echo
   them back. In QEMU, type into the terminal.
8. `**` **Use a ROM function.** The ESP32 ROM exports `ets_printf` (address
   in `~/esp/esp-idf/components/esp_rom/esp32/ld/esp32.rom.ld`). Call it
   with `callx0`. ROM functions use the windowed ABI. Why does that break,
   and what is required (see exercise 11)?
9. `**` **Write `mkimage.py --hash`.** Set byte 23 to 1 and append the
   SHA-256 of the image. Verify with `esptool.py image_info` and compare
   against `esptool.py elf2image` (without `--dont-append-digest`).

## Projects

10. `***` **C runtime.** Add a stack (`movi`/`l32r` into `a1`), zero
    `.bss`, copy `.data`, and call a `main()` written in C, compiled with
    `xtensa-esp32-elf-gcc -mabi=call0 -ffreestanding -nostdlib`.
11. `***` **Exception vectors.** Write a vector table, point `VECBASE` at
    it, and implement window overflow/underflow handlers to enable the
    default windowed ABI (and ROM calls). Trigger a deliberate
    `LoadStoreError` and print `EXCCAUSE` / `EPC1`.
12. `***` **Blink.** Drive a GPIO (GPIO_ENABLE / GPIO_OUT registers). QEMU
    shows no LED; verify by reading the registers back in GDB, then test on
    a real board.
13. `****` **Real hardware.** Flash `build/hello.bin` to a real ESP32 at
    `0x1000` (`esptool.py --chip esp32 write_flash 0x1000 build/hello.bin`).
    Test whether removing the WDT code causes a reboot.
14. `****` **NASM as an Xtensa byte emitter.** Write NASM macros
    (`%macro`) that emit Xtensa encodings with `db` (e.g. `movi a5, 0` ->
    `52 a0 00`). Re-create `hello.s` as `hello.asm`, build it with
    `nasm -f bin`, wrap it with a modified `mkimage.py` (raw bin + load
    address instead of ELF), and boot it. Compare the output bytes with
    `objdump`.

## Checkpoint answers (Lesson 5)

1. The ROM loads the bootloader while still running; the bootloader in turn
   loads the app's data into `0x3FFB_0000...` while running. It must avoid
   both the ROM's working RAM and the app's RAM; the top of SRAM1
   (`0x3FFF_0000`) satisfies both, hence its use in the POC too.
2. The `map` segments: DROM (`0x3F40_xxxx`) and IROM (`0x400D_xxxx`).
3. UART0 TX FIFO -> GPIO1 (TXD0) -> USB-serial chip on a dev board (in
   QEMU: the terminal).
4. With 250 ms: `tick=0, 25, 50, 75, ...` (100 ticks per second / 4).
   Without line 22, `hello_task` never blocks: at priority 5 it monopolises
   its core and the output floods. After 5 s the ESP-IDF **task watchdog**
   detects that the idle task on that core (priority 0) never ran:

   ```text
   E (6790) task_wdt: Task watchdog got triggered. The following tasks/users did not reset the watchdog in time:
   E (6790) task_wdt:  - IDLE0 (CPU 0)
   E (6790) task_wdt: Tasks currently running:
   E (6790) task_wdt: CPU 0: hello
   ```

   By default it only reports (every 5 s); it does not reset. In an RTOS, a
   task that never blocks starves everything below its priority.
