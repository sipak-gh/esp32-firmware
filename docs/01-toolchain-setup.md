# Lesson 1: Toolchain Setup (Tools & Dependencies)

> **Goal:** list each tool the course requires, its version, and its role.

---

## 1.1 Host

Ubuntu 22.04.5 LTS, x86_64, with `git`, `curl` and `python3` 3.10. Tools
below are installed under `$HOME`; adapt paths if installing system-wide.

---

## 1.2 Inventory

| # | Tool | Version | Purpose |
|---|---|---|---|
| 1 | **uv** (Astral) | 0.13.5 | Provides a standalone Python with `venv`/`pip` (the distro Python 3.10 lacks `ensurepip`). |
| 2 | **CPython** | 3.12.15 | Interpreter for the ESP-IDF virtual environment. |
| 3 | **ESP-IDF** | v5.5.6 | Espressif SDK: FreeRTOS, build system, `idf.py`, `idf_tools.py`. |
| 4 | **ESP-IDF Python env** | Python 3.12 venv | `esptool` 4.12.0 and `idf.py` dependencies. |
| 5 | **xtensa-esp-elf** (GCC + binutils) | 14.2.0, 2.43.1 (`esp-14.2.0_20260121`) | Xtensa assembler (`-as`), linker (`-ld`), `-objdump`, `-readelf`, cross compiler. |
| 6 | **xtensa-esp-elf-gdb** | 17.1_20260402 | Debugger (Lesson 7.8). |
| 7 | **CMake** | 3.30.2 | ESP-IDF build system generator. |
| 8 | **Ninja** | 1.12.1 | ESP-IDF build executor. |
| 9 | **QEMU (Espressif fork)** | 9.2.2 (`esp_develop_9.2.2_20260417`) | Emulates an ESP32 (`-machine esp32`); upstream QEMU has no ESP32 machine. |
| 10 | **QEMU runtime libraries** | Ubuntu 22.04 packages (1.5) | Shared libraries the QEMU binary links against. |
| 11 | **GNU Make** | 4.3 | Drives the bare-metal build (`hello-asm/Makefile`). |
| 12 | **NASM** | 2.15.05 | x86 assembler, used only for comparison (Lesson 2). |
| 13 | **pypdf** (optional) | 6.21.2 | Text search of the reference PDFs (1.8). |

Also installed by ESP-IDF but unused: `esp32ulp-elf` 2.38_20240113 (ULP
toolchain), `openocd-esp32` v0.12.0-esp32-20260831 (JTAG).

Not required: host `gcc` (ESP-IDF uses its cross compiler) or a physical
ESP32 (everything runs in QEMU).

---

## 1.3 Python

```bash
curl -LsSf https://astral.sh/uv/install.sh | env UV_NO_MODIFY_PATH=1 sh
~/.local/bin/uv python install 3.12
```

---

## 1.4 ESP-IDF

```bash
mkdir -p ~/esp && cd ~/esp
git clone --depth 1 -b v5.5.6 --recursive --shallow-submodules \
    https://github.com/espressif/esp-idf.git

export PATH=~/.local/share/uv/python/cpython-3.12-linux-x86_64-gnu/bin:$PATH
cd ~/esp/esp-idf
./install.sh esp32                                  # ESP32 target only
python3 tools/idf_tools.py install cmake ninja      # not bundled on Linux
python3 tools/idf_tools.py install qemu-xtensa
```

---

## 1.5 QEMU runtime libraries

The Espressif QEMU binary is dynamically linked against SDL2, slirp and
their audio dependencies, which a minimal install lacks. List unresolved
libraries with `ldd .../qemu-system-xtensa | grep "not found"`.

| Library | Ubuntu package |
|---|---|
| `libSDL2-2.0.so.0`, `libslirp.so.0` | `libsdl2-2.0-0`, `libslirp0` |
| `libasound.so.2`, `libpulse.so.0`, `libXss.so.1`, `libdecor-0.so.0` | `libasound2`, `libpulse0`, `libxss1`, `libdecor-0-0` |
| `libasyncns.so.0`, `libsndfile.so.1` | `libasyncns0`, `libsndfile1` |
| `libFLAC.so.8`, `libogg.so.0`, `libopus.so.0`, `libvorbis.so.0`, `libvorbisenc.so.2` | `libflac8`, `libogg0`, `libopus0`, `libvorbis0a`, `libvorbisenc2` |

With root: `sudo apt install <packages>`. Without root, extract them locally:

```bash
mkdir -p /tmp/qdeb ~/opt/qemu-libs && cd /tmp/qdeb
apt-get download libsdl2-2.0-0 libslirp0 libasound2 libpulse0 libxss1 \
    libdecor-0-0 libasyncns0 libsndfile1 libflac8 libogg0 libopus0 \
    libvorbis0a libvorbisenc2
for f in *.deb; do dpkg -x "$f" ~/opt/qemu-libs; done
```

`libpulsecommon` lives in a `pulseaudio/` subdirectory, so `LD_LIBRARY_PATH`
needs both directories (1.7). `export.sh` probes each tool by executing it;
if `LD_LIBRARY_PATH` is unset at that point, QEMU is omitted from `PATH`.

---

## 1.6 GNU Make and NASM

```bash
cd /tmp && apt-get download make nasm
dpkg -x make_*.deb ~/opt/make
dpkg -x nasm_*.deb ~/opt/nasm
```

(Or `sudo apt install make nasm`.)

---

## 1.7 Activating the environment (every new terminal)

Run in this order (interactively or from a shell profile):

```bash
L=~/opt/qemu-libs/usr/lib/x86_64-linux-gnu
export LD_LIBRARY_PATH=$L:$L/pulseaudio                        # 1. QEMU libs first
export PATH=~/opt/make/usr/bin:~/opt/nasm/usr/bin:$PATH         # 2. make + nasm
export PATH=~/.local/share/uv/python/cpython-3.12-linux-x86_64-gnu/bin:$PATH
. ~/esp/esp-idf/export.sh                                       # 3. ESP-IDF, toolchain, QEMU
```

Sanity check:

```bash
which qemu-system-xtensa xtensa-esp32-elf-as esptool.py idf.py make nasm
qemu-system-xtensa --version
xtensa-esp32-elf-as --version | head -1
```

---

## 1.8 Optional: searching the reference PDFs

Facts in the downloaded PDFs (for example the memory-ordering section of the
Xtensa ISA manual quoted in Lesson 7) can be checked with the **pypdf**
library (6.21.2) through uv. Nothing is installed into a project; uv builds a
throw-away environment cached in `~/.cache/uv`. Run from the repository root
(`~/esp32-firmware`):

```bash
~/.local/bin/uv run --with pypdf python -c '
import pypdf
r = pypdf.PdfReader("docs/references/xtensa_isa_reference_manual.pdf")
print(r.pages[62].extract_text())          # page 63 = section 3.8.3'
```

A PDF viewer is an alternative.

Next: [Lesson 2: Why not NASM?](02-why-not-nasm.md)
