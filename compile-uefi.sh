#!/bin/bash
v1 . ./bus/ ./elf/ ./interrupts/ ./low/ ./low/x64/ ./memory/ ./scheduler/ ./system-calls/ ./utility/ ./file-systems/ ./file-systems/ext2/ ./file-systems/memory-file-system/ ./devices/ ./devices/console/ ./devices/gpu/ ./devices/gpu/qemu/ ./devices/keyboard/ ./devices/keyboard/ps2/ ./devices/storage/ata/ ./devices/storage/nvme/ ./build/entry.o ./build/cpu.o -o kernel -shared -system
