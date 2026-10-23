# hello.s - bare-metal "Hello, World!" for the ESP32 (Xtensa LX6).
#
# The ESP32 mask ROM loads this program from flash offset 0x1000 into RAM
# and jumps to _start. Nothing else runs: no bootloader, no SDK, no C runtime.
#
# What it does:
#   1. Disables the two watchdogs the ROM armed (else a real chip resets).
#   2. Writes a string to UART0, which the ROM already set to 115200 baud.
#   3. Spins forever.
#
# Register use:
#   a2  pointer to the next character of the message
#   a3  current character
#   a4  watchdog unlock key, then UART0 status register address
#   a5  zero (for the watchdogs), then UART0 TX FIFO fill level
#   a6  watchdog register address, then UART0 TX FIFO address

# ---------------------------------------------------------------------------
# Hardware register addresses (ESP32 Technical Reference Manual; also in
# ESP-IDF components/soc/esp32/register/soc/*.h).
# ---------------------------------------------------------------------------
    .set TIMG0_WDTCONFIG0,  0x3FF5F048  # Timer Group 0 watchdog config
    .set TIMG0_WDTWPROTECT, 0x3FF5F064  # Timer Group 0 watchdog write-protect
    .set RTC_WDTCONFIG0,    0x3FF4808C  # RTC watchdog config
    .set RTC_WDTWPROTECT,   0x3FF480A4  # RTC watchdog write-protect
    .set WDT_UNLOCK_KEY,    0x50D83AA1  # value that unlocks either watchdog
    .set UART0_STATUS,      0x3FF4001C  # bits [23:16] = bytes in TX FIFO
    .set UART0_FIFO,        0x60000000  # write a byte here to transmit it
                                        # (AHB address; ESP32 errata say not
                                        # to use the 0x3FF40000 DPORT alias)

# ---------------------------------------------------------------------------
# The message. Placed in DRAM by link.ld, because it is read one byte at a
# time and IRAM only allows 32-bit loads.
# ---------------------------------------------------------------------------
    .section .rodata
message:
    .asciz "Hello, World! (from bare-metal Xtensa assembly)\r\n"

# ---------------------------------------------------------------------------
# Code. Placed in IRAM by link.ld.
# ---------------------------------------------------------------------------
    .section .text

# Literal pool. An Xtensa instruction is at most 24 bits wide, so it cannot
# carry a 32-bit constant. Constants live here and are fetched with l32r,
# which addresses them relative to the PC. l32r can only look backwards and
# needs 4-byte-aligned words, so the pool sits before the code, aligned.
    .align 4
lit_wdt_key:        .word WDT_UNLOCK_KEY
lit_timg0_wdtwp:    .word TIMG0_WDTWPROTECT
lit_timg0_wdtcfg:   .word TIMG0_WDTCONFIG0
lit_rtc_wdtwp:      .word RTC_WDTWPROTECT
lit_rtc_wdtcfg:     .word RTC_WDTCONFIG0
lit_message:        .word message        # the linker fills in the address
lit_uart_status:    .word UART0_STATUS
lit_uart_fifo:      .word UART0_FIFO

# Entry point. Global so that link.ld's ENTRY(_start) can find it; the linker
# stores its address in the ELF header and mkimage.py copies it to the image.
    .global _start
_start:

# Step 1: disable the watchdogs. Their config registers are write-protected:
# write the key to WPROTECT, then 0 to CONFIG0, which clears the enable bit.
# Xtensa may reorder memory accesses, so memw makes the unlock land first.
    l32r    a4, lit_wdt_key         # a4 = unlock key
    movi    a5, 0                   # a5 = 0

    l32r    a6, lit_timg0_wdtwp
    s32i    a4, a6, 0               # unlock the Timer Group 0 watchdog
    memw
    l32r    a6, lit_timg0_wdtcfg
    s32i    a5, a6, 0               # disable it

    l32r    a6, lit_rtc_wdtwp
    s32i    a4, a6, 0               # unlock the RTC watchdog
    memw
    l32r    a6, lit_rtc_wdtcfg
    s32i    a5, a6, 0               # disable it

# Step 2: send the message, one byte at a time.
    l32r    a2, lit_message         # a2 = &message[0]
    l32r    a4, lit_uart_status     # a4 = &UART0_STATUS
    l32r    a6, lit_uart_fifo       # a6 = &UART0_FIFO

next_char:
    l8ui    a3, a2, 0               # a3 = *a2 (load byte, zero-extended)
    beqz    a3, halt                # reached the terminating '\0'? stop

wait_for_room:
    memw                            # finish the previous FIFO write first,
                                    # so the status read below is current
    l32i    a5, a4, 0               # a5 = UART0_STATUS
    extui   a5, a5, 16, 8           # a5 = bits [23:16] = TX FIFO fill level
    bgeui   a5, 128, wait_for_room  # FIFO (128 bytes) full? check again

    s32i    a3, a6, 0               # queue the byte for transmission
                                    # (no memw needed before it: the store
                                    # cannot run until the branch above has
                                    # seen the status value)
    addi    a2, a2, 1               # advance to the next character
    j       next_char

# Step 3: nothing left to do. Spin forever.
halt:
    j       halt
