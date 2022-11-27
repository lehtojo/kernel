#!/bin/bash
qemu-system-x86_64 -serial stdio --no-reboot -smp 2 -m 1024 -hda ./build/boot.bin
