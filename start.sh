#!/bin/bash
qemu-system-x86_64 $@ -cpu Broadwell -vga std -machine q35 -serial stdio --no-reboot -smp 2 -m 2048 \
	-hda build/boot.iso \
	-drive file=filesystem.ext2,if=none,id=nvm \
	-device nvme,serial=deadbeef,drive=nvm
