#!/bin/bash
qemu-system-x86_64 -vga std -machine q35 -serial stdio --no-reboot -smp 2 -m 2048 -hda build/boot.iso
