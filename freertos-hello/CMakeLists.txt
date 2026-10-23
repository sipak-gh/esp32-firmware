# Top-level CMake file of an ESP-IDF project. cmake_minimum_required, include
# and project must appear in this order.

cmake_minimum_required(VERSION 3.16)

# Pull in ESP-IDF's build system ($IDF_PATH is set by export.sh).
include($ENV{IDF_PATH}/tools/cmake/project.cmake)

# Build only the components our code needs (plus ESP-IDF's core ones such as
# freertos), instead of every component in ESP-IDF. Cuts build time.
idf_build_set_property(MINIMAL_BUILD ON)

# Project name; becomes build/freertos_hello.bin and build/freertos_hello.elf.
project(freertos_hello)
