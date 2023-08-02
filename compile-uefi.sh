#!/bin/bash
as ./low/x64/cpu.asm -o ./build/cpu.o

if [[ $? != 0 ]]; then
echo "Failed to compile helper assembly files"
exit 1
fi

v1 . ./bus/ ./elf/ ./interrupts/ ./low/ ./low/x64/ ./memory/ ./scheduler/ ./system-calls/ ./utility/ ./file-systems/ ./file-systems/ext2/ ./file-systems/memory-file-system/ ./devices/ ./devices/console/ ./devices/gpu/ ./devices/gpu/gop/ ./devices/gpu/qemu/ ./devices/keyboard/ ./devices/keyboard/ps2/ ./devices/storage/ata/ ./devices/storage/nvme/ ./time/ ./build/entry.o ./build/cpu.o -o kernel -shared -system
