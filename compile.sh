#!/bin/bash
rm -rf build/boot/
rm -rf build/iso/
rm build/boot.bin
rm build/boot.iso
rm build/cpu.o
rm build/kernel.bin

mkdir -p build/boot/
mkdir -p build/iso/boot/grub/

cp boot/grub.cfg build/iso/boot/grub/grub.cfg

as ./low/x64/cpu.asm -o ./build/cpu.o

if [[ $? != 0 ]]; then
echo "Failed to compile helper assembly files"
exit 1
fi

v1 . ./bus/ ./elf/ ./interrupts/ ./low/ ./low/x64/ ./memory/ ./scheduler/ ./system-calls/ ./utility/ ./file-systems/ ./file-systems/ext2/ ./file-systems/memory-file-system/ ./devices/ ./devices/console/ ./devices/gpu/ ./devices/gpu/qemu/ ./devices/keyboard/ps2/ ./devices/storage/ata/ ./devices/storage/nvme/ ./build/entry.o ./build/cpu.o -binary -o ./build/kernel.bin -base 0xffff800000104000 -system -a

if [[ $? != 0 ]]; then
echo "Failed to compile kernel"
exit 1
fi

nasm -felf64 boot/multiboot_header.asm -o build/boot/multiboot_header.o
nasm -felf64 boot/boot.asm -o build/boot/boot.o

ld -n -T boot/linker.ld -o build/boot.bin build/boot/multiboot_header.o build/boot/boot.o

if [[ $? != 0 ]]; then
echo "Failed to create the kernel file"
exit 1
fi

cp build/boot.bin build/iso/boot/boot.bin

grub-mkrescue -o build/boot.iso build/iso 2> /dev/null
