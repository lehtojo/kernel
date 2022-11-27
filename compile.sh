#!/bin/bash
nasm bootloader.asm -f bin -o ./build/bootloader.bin

if [[ $? != 0 ]]; then
echo "Failed to compile bootloader"
exit 1
fi

as cpu.asm -o ./build/cpu.o

if [[ $? != 0 ]]; then
echo "Failed to compile helper assembly files"
exit 1
fi

v1 . ./utility/ ./build/entry.o ./build/cpu.o -binary -o ./build/kernel.bin

if [[ $? != 0 ]]; then
echo "Failed to compile kernel"
exit 1
fi

# Create an empty boot file
dd if=/dev/zero of=./build/boot.bin bs=1 count=65536 status=none

# Copy the bootloader
dd if=./build/bootloader.bin of=./build/boot.bin bs=1 status=none conv=notrunc

# Copy the kernel
dd if=./build/kernel.bin of=./build/boot.bin bs=1 seek=512 status=none conv=notrunc
