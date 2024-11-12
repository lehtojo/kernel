# Kernel
Small kernel built with [Vivid](https://github.com/lehtojo/vivid-2) programming language that aims to be compatible with Linux programs.

https://github.com/user-attachments/assets/63efe5c8-cffd-4d64-897f-17d26b57c33c

## Getting started
1. Install the following dependencies:
```bash
sudo apt install nasm qemu-system-x86 xorriso grub-common grub-pc mtools clang lld make
```
2. Install or build the [compiler](https://github.com/lehtojo/vivid-2) for the kernel project. Remember to add the compiler (`v1`) to the path.
3. Build the kernel by executing `./compile-uefi.sh`
4. (Optional) Done. If you have the kernel loader in the same parent folder, copy the generated kernel image to the loader by executing `cp ./kernel.so ../kernel-loader/KERNEL.SO`
