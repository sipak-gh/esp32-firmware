# Makefile - build the bare-metal ESP32 "Hello, World!" and run it in QEMU.
#
#   src/hello.s --as--> build/hello.o --ld--> build/hello.elf
#       --mkimage.py--> build/hello.bin (ESP32 image) + build/flash.bin (4 MB)
#
# Needs xtensa-esp32-elf-as/ld, python3 and qemu-system-xtensa on PATH
# (see docs/01-toolchain-setup.md).

# Plain `make` builds the flash image (otherwise make builds the first rule).
.DEFAULT_GOAL := build/flash.bin

# Assemble: turn source text into machine code (an object file).
build/hello.o: src/hello.s
	mkdir -p build
	xtensa-esp32-elf-as -o $@ $<

# Link: give every section its final address, using link.ld.
build/hello.elf: build/hello.o link.ld
	xtensa-esp32-elf-ld -T link.ld -o $@ $<

# Package: convert the ELF into a bootable ESP32 image and a flash image.
build/flash.bin: build/hello.elf tools/mkimage.py
	python3 tools/mkimage.py $< build/hello.bin $@

# Boot the flash image on an emulated ESP32. Quit with Ctrl-A, then X.
run: build/flash.bin
	qemu-system-xtensa -nographic -machine esp32 \
	    -drive file=$<,if=mtd,format=raw

clean:
	rm -rf build

.PHONY: run clean
