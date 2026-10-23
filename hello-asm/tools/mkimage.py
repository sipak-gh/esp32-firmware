#!/usr/bin/env python3
"""mkimage.py - turn an ELF file into an image the ESP32 ROM can boot.

Usage: mkimage.py <input.elf> <output image.bin> <output flash.bin>

  image.bin  the ESP32 image (what you would flash at offset 0x1000)
  flash.bin  a complete 4 MB flash with image.bin at 0x1000 (for QEMU)

Image layout (see docs/04-esp32-boot-and-image-format.md):
  24-byte header | segments (address, length, data)... | padding | checksum
"""

import struct
import sys

elf_path, image_path, flash_path = sys.argv[1:4]

with open(elf_path, "rb") as f:
    elf = f.read()

# --- 1. Read the ELF file ---------------------------------------------------
# From the ELF32 header: e_entry (offset 24) and e_phoff (offset 28), then
# e_phentsize and e_phnum (offset 42): the program-header table location,
# entry size and entry count.
entry, phoff = struct.unpack_from("<II", elf, 24)
phentsize, phnum = struct.unpack_from("<HH", elf, 42)

# Each program header describes a segment. The first five 32-bit fields are
# p_type, p_offset (where the bytes are in the file), p_vaddr (where they go
# in memory), p_paddr and p_filesz (how many bytes). Type 1 (PT_LOAD) marks
# segments that must be loaded into memory.
segments = []
for i in range(phnum):
    p_type, p_offset, p_vaddr, _p_paddr, p_filesz = struct.unpack_from(
        "<5I", elf, phoff + i * phentsize)
    if p_type == 1:
        segments.append((p_vaddr, elf[p_offset:p_offset + p_filesz]))

# --- 2. Image header (24 bytes, little-endian) ------------------------------
image = bytearray(struct.pack(
    "<BBBBIB3sHBHH4sB",
    0xE9,            # magic number; the ROM refuses anything else
    len(segments),   # segment count
    2,               # SPI flash mode: 2 = DIO
    0x20,            # high nibble: flash size (2 = 4 MB);
                     # low nibble: flash clock (0 = 40 MHz)
    entry,           # address the ROM jumps to
    0xEE,            # write-protect pin: 0xEE = none
    b"\x00" * 3,     # SPI pin drive strengths: defaults
    0,               # chip ID: 0 = ESP32
    0,               # minimum chip revision (legacy field)
    0,               # minimum chip revision (major * 100 + minor)
    0xFFFF,          # maximum chip revision: 0xFFFF = no limit
    b"\x00" * 4,     # reserved
    0,               # 1 would mean a SHA-256 digest follows the image
))

# --- 3. Segments ------------------------------------------------------------
# Each segment is: load address, length, data. Lengths must be multiples of
# 4, so data is zero-padded. The checksum starts at 0xEF and XORs in every
# data byte (headers are not included).
checksum = 0xEF
for address, data in segments:
    data += b"\x00" * (-len(data) % 4)
    image += struct.pack("<II", address, len(data)) + data
    for byte in data:
        checksum ^= byte

# --- 4. Checksum ------------------------------------------------------------
# Zero-pad so that the checksum byte ends the image on a 16-byte boundary.
image += b"\x00" * (15 - len(image) % 16)
image.append(checksum)

with open(image_path, "wb") as f:
    f.write(image)

# --- 5. Flash image ---------------------------------------------------------
# Erased flash reads as 0xFF. The ROM looks for an image at offset 0x1000.
flash = bytearray(b"\xFF" * (4 * 1024 * 1024))
flash[0x1000:0x1000 + len(image)] = image

with open(flash_path, "wb") as f:
    f.write(flash)
