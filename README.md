# Kernel

## Getting started
Install the dependencies:
```bash
sudo apt install nasm qemu-system-x86 xorriso grub-common grub-pc mtools clang lld
```

You'll also need [OVMF](https://github.com/tianocore/tianocore.github.io/wiki/How-to-run-OVMF). [Tianocore](https://github.com/tianocore/tianocore.github.io) offers [prebuilt images](https://www.kraxel.org/repos/):

1. Download `jenkins/edk2/edk2.git-ovmf-x64-...`
2. Unarchive the downloaded file
3. Place `usr/share/edk2.git/ovmf-x64/` folder into your home folder