#!/bin/sh
dd if=/dev/zero of=filesystem.ext2 bs=1M count=16
mkfs.ext2 -d ./root/ filesystem.ext2
