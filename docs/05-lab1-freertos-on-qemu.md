# Lesson 5: Lab 1, FreeRTOS on QEMU (the "known good" baseline)

> **Goal:** verify the emulator and toolchain with a production-style
> firmware (an ESP-IDF application on FreeRTOS) before writing firmware from
> scratch.
>
> Project folder: [`freertos-hello/`](../freertos-hello). Snippets are copied
> from the source with their original line numbers.

## 5.1 Why do this first?

Bare-metal code that prints nothing may fail because of the code or the
setup. A known-good firmware isolates the setup: if FreeRTOS boots in QEMU,
the emulator, flash image layout and serial console work.

## 5.2 What is FreeRTOS, and where does it come from here?

**FreeRTOS** is a small real-time operating system kernel (MIT licence). It
provides **tasks** (threads), a pre-emptive priority **scheduler**, queues,
semaphores, mutexes and software timers. The kernel is a few C files
(`tasks.c`, `queue.c`, `list.c`, `timers.c`) plus a CPU-specific **port**
(context switching in assembly).

Espressif ships an SMP-capable FreeRTOS fork inside ESP-IDF
(`~/esp/esp-idf/components/freertos/`); its Xtensa port schedules tasks on
both cores. Cloning ESP-IDF ([Lesson 1](01-toolchain-setup.md)) therefore
also obtains FreeRTOS.

Further reading: `docs/references/freertos_kernel_book_v1.1.0.pdf`
(*Mastering the FreeRTOS Real Time Kernel*) and
`docs/references/espidf_v5.5_freertos.html`.

## 5.3 The application

The project has three files, 56 lines in total.

### `CMakeLists.txt`: the project

`freertos-hello/CMakeLists.txt`, lines 1-14:

```cmake
  1  # Top-level CMake file of an ESP-IDF project. cmake_minimum_required, include
  2  # and project must appear in this order.
  3
  4  cmake_minimum_required(VERSION 3.16)
  5
  6  # Pull in ESP-IDF's build system ($IDF_PATH is set by export.sh).
  7  include($ENV{IDF_PATH}/tools/cmake/project.cmake)
  8
  9  # Build only the components our code needs (plus ESP-IDF's core ones such as
 10  # freertos), instead of every component in ESP-IDF. Cuts build time.
 11  idf_build_set_property(MINIMAL_BUILD ON)
 12
 13  # Project name; becomes build/freertos_hello.bin and build/freertos_hello.elf.
 14  project(freertos_hello)
```

* Line 7 includes ESP-IDF's build system. `$IDF_PATH` is set by sourcing
  `export.sh` (Lesson 1.7).
* Line 11, `MINIMAL_BUILD`: instead of every component (the default: Wi-Fi,
  Bluetooth, HTTP server, ...), ESP-IDF compiles only `main`, its
  dependencies and the core components, FreeRTOS among them.
* Line 14 names the project and hence the output files.

### `main/CMakeLists.txt`: the component

`freertos-hello/main/CMakeLists.txt`, lines 1-3:

```cmake
  1  # The "main" component: the application's own code. FreeRTOS is an ESP-IDF
  2  # core component and is always available, so no REQUIRES line is needed.
  3  idf_component_register(SRCS "main.c")
```

ESP-IDF builds everything as **components**; the application code is the
component `main`, with a single source file.

### `main/main.c`: the code

`freertos-hello/main/main.c`, lines 9-39:

```c
  9  #include <stdio.h>              /* printf: ESP-IDF routes it to UART0 */
 10  #include "freertos/FreeRTOS.h"  /* must come before any other FreeRTOS header */
 11  #include "freertos/task.h"      /* xTaskCreate, vTaskDelay, xTaskGetTickCount */
 12
 13  /* Body of our task. A FreeRTOS task is a function that never returns. */
 14  static void hello_task(void *arg)
 15  {
 16      for (;;) {
 17          /* Ticks since the scheduler started (CONFIG_FREERTOS_HZ per sec). */
 18          printf("Hello from a FreeRTOS task! tick=%lu\n",
 19                 (unsigned long)xTaskGetTickCount());
 20
 21          /* Block this task for 1000 ms; the scheduler runs others meanwhile. */
 22          vTaskDelay(pdMS_TO_TICKS(1000));
 23      }
 24  }
 25
 26  void app_main(void)
 27  {
 28      /* Create the task:
 29       *   hello_task  function to run
 30       *   "hello"     name (for debugging)
 31       *   2048        stack size; in ESP-IDF this is in BYTES, not words
 32       *   NULL        argument passed to hello_task
 33       *   5           priority (higher number = higher priority)
 34       *   NULL        we don't need the task handle back */
 35      xTaskCreate(hello_task, "hello", 2048, NULL, 5, NULL);
 36
 37      /* Returning is fine: ESP-IDF deletes the "main" task, and hello_task
 38       * keeps running. */
 39  }
```

* The application defines no `main()`. ESP-IDF's startup code initialises
  the chip, starts the FreeRTOS scheduler and calls `app_main()` from a task
  named `main`.
* Line 35: `xTaskCreate` registers `hello_task` with the scheduler, which
  runs it whenever it is the highest-priority ready task. At priority 5
  (above the `main` task's 1) it runs immediately, before `app_main`
  returns; hence its first line precedes `Returned from app_main()` below.
* Line 16, `for (;;)`: a task function must never return. A task that ends
  must call `vTaskDelete(NULL)`.
* Line 19, `xTaskGetTickCount()`: the scheduler is driven by a periodic
  **tick** interrupt. `CONFIG_FREERTOS_HZ=100` in this project's `sdkconfig`
  (the ESP-IDF default) gives 100 ticks per second.
* Line 22: `vTaskDelay` blocks the task, removing it from the CPU until
  `pdMS_TO_TICKS(1000)` = 100 ticks have elapsed; meanwhile the CPU runs
  other tasks or the idle task.
* Line 37: returning from `app_main` makes ESP-IDF delete the `main` task;
  `hello_task` keeps the firmware running.

## 5.4 Build

```bash
# activate the environment first (Lesson 1, section 1.7)
cd ~/esp32-firmware/freertos-hello
idf.py set-target esp32      # generates sdkconfig for the ESP32
idf.py build                 # CMake + Ninja; ~1-2 minutes the first time
```

`sdkconfig` holds every configuration option (edited with
`idf.py menuconfig`); being generated, it is not committed.

Outputs in `build/`:

| File | Flash offset | What |
|---|---|---|
| `bootloader/bootloader.bin` | `0x1000` | 2nd-stage bootloader |
| `partition_table/partition-table.bin` | `0x8000` | partition table |
| `freertos_hello.bin` | `0x10000` | the app (FreeRTOS + application code), 136,256 bytes |
| `freertos_hello.elf` | - | same app with symbols, for GDB/objdump |
| `flash_args` | - | offset/file list used by esptool |

## 5.5 Run in QEMU, method A: by hand (recommended for learning)

QEMU emulates a flash chip and takes one file covering the whole flash:

```bash
cd build
esptool.py --chip esp32 merge_bin --fill-flash-size 4MB -o flash_image.bin @flash_args
qemu-system-xtensa -nographic -machine esp32 \
    -drive file=flash_image.bin,if=mtd,format=raw
# quit: Ctrl-A then X
```

* `-machine esp32` selects Espressif's ESP32 board model (only in their fork).
* `-drive ...,if=mtd` attaches the file as the SPI flash.
* `-nographic` connects UART0 to the terminal.

## 5.6 Run in QEMU, method B: `idf.py qemu`

```bash
idf.py qemu            # builds, merges flash, creates an eFuse file, runs QEMU
idf.py qemu monitor    # same, but attaches idf.py's serial monitor
```

The resulting QEMU command line:

```text
qemu-system-xtensa -M esp32 -m 4M \
  -drive file=build/qemu_flash.bin,if=mtd,format=raw \
  -drive file=build/qemu_efuse.bin,if=none,format=raw,id=efuse \
  -global driver=nvram.esp32.efuse,property=drive,value=efuse \
  -global driver=timer.esp32.timg,property=wdt_disable,value=true \
  -nic user,model=open_eth -nographic -serial mon:stdio
```

`wdt_disable`: QEMU models the Timer Group watchdog; idf.py disables it for
convenience.

## 5.7 Expected output (method A)

Reference output:

```text
ets Jul 29 2019 12:21:46
rst:0x1 (POWERON_RESET),boot:0x12 (SPI_FAST_FLASH_BOOT)
...
load:0x3fff0030,len:6180          <- ROM loads the 2nd-stage bootloader
load:0x40078000,len:15852
load:0x40080400,len:3876
entry 0x4008063c
I (686) boot: ESP-IDF v5.5.6 2nd stage bootloader
...
I (760) boot: Partition Table:
...
I (761) boot:  2 factory          factory app      00 00 00010000 00100000
I (819) esp_image: segment 0: paddr=00010020 vaddr=3f400020 size=06be4h ( 27620) map
I (845) esp_image: segment 1: paddr=00016c0c vaddr=3ffb0000 size=02624h (  9764) load
I (870) esp_image: segment 2: paddr=00019238 vaddr=40080000 size=06de0h ( 28128) load
I (899) esp_image: segment 3: paddr=00020020 vaddr=400d0020 size=0b778h ( 46968) map
I (925) esp_image: segment 4: paddr=0002b7a0 vaddr=40086de0 size=05c48h ( 23624) load
I (950) esp_image: segment 5: paddr=000313f0 vaddr=50000000 size=00020h (    32) load
I (1037) boot: Loaded app from partition at offset 0x10000
I (1052) cpu_start: Multicore app
...
I (1795) cpu_start: cpu freq: 160000000 Hz
I (1795) app_init: Project name:     freertos_hello
...
I (1834) main_task: Started on CPU0
I (1834) main_task: Calling app_main()
Hello from a FreeRTOS task! tick=0
I (1834) main_task: Returned from app_main()
Hello from a FreeRTOS task! tick=100
Hello from a FreeRTOS task! tick=200
Hello from a FreeRTOS task! tick=300
...                                 <- one line per second, forever
```

The `I (...)` numbers are milliseconds since boot; values vary slightly
between runs.

### Connect it to Lesson 4

* `load:...`/`entry ...` lines: the ROM (stage 1) loading the bootloader
  from `0x1000`.
* `I (...) boot:` lines: the 2nd-stage bootloader. `map` segments are
  flash-mapped through the MMU (`0x3F40_xxxx` DROM, `0x400D_xxxx` IROM);
  `load` segments are copied to RAM.
* `cpu_start`, `app_init`, `main_task`: the application (stage 3) and
  FreeRTOS, interleaved with the task's `printf` lines.

## 5.8 Checkpoint questions

1. Why does the bootloader's first segment load at `0x3FFF_0030` rather than
   `0x3FFB_0000` like the app's data?
2. Which segments can exist only after stage 2 has configured the MMU?
3. Where does `printf` output physically go?
4. Change `vTaskDelay` on line 22 to `pdMS_TO_TICKS(250)`. Which tick values
   result? What happens if line 22 is deleted entirely? (Hint: the task
   watchdog, and the idle task.)

Answers are at the end of [Lesson 8](08-exercises.md).

Next: [Lesson 6: Xtensa Assembly Primer](06-xtensa-assembly-primer.md)
