[bits 32]
global start
start:

; Disable interrupts
cli

; Save the boot information provided by the multiboot protocol
mov dword [multiboot_information], ebx

; Register the global descriptor table
lgdt [gdt32_descriptor]

mov eax, cr0
or eax, 1
mov cr0, eax

mov ax, DATA_SEGMENT_32
mov ds, ax
mov ss, ax
mov es, ax
mov fs, ax
mov gs, ax

; Setup the stack
mov ebp, 0x200000
mov esp, ebp

; Create virtual mapping for the page map:
; Physical address: 0xF000000

; Disable the old paging
mov eax, cr0
and eax, 01111111111111111111111111111111b
mov cr0, eax

; Zero out all the page entries
VIRTUAL_MAP_BASE equ 0xF000000

PAGE_MAP_BASE equ 0x10000000
PAGE_MAP_END equ (PAGE_MAP_BASE + (L4_COUNT + L3_COUNT + L2_COUNT + L1_COUNT) * 8)

L4_BASE equ (PAGE_MAP_BASE)
L3_BASE equ (PAGE_MAP_BASE + L4_COUNT * 8)
L2_BASE equ (PAGE_MAP_BASE + (L4_COUNT + L3_COUNT) * 8)
L1_BASE equ (PAGE_MAP_BASE + (L4_COUNT + L3_COUNT + L2_COUNT) * 8)

VIRTUAL_MAP_L3_BASE equ (VIRTUAL_MAP_BASE)
VIRTUAL_MAP_L2_BASE equ (VIRTUAL_MAP_BASE + 0x1000)
VIRTUAL_MAP_L1_BASE equ (VIRTUAL_MAP_BASE + 0x3000)

VIRTUAL_MAP_L2_SIZE equ 0x1000

mov edi, VIRTUAL_MAP_BASE
xor eax, eax
mov ecx, (PAGE_MAP_END - VIRTUAL_MAP_BASE)
rep stosb

; Point the L3 entries to L2 entries
; Support ~2GB page map, so we need two L3 entries
; L3: 0xF000000
; 1th L2: 0xF001000
; 2th L2: 0xF002000
mov dword [abs VIRTUAL_MAP_BASE], (VIRTUAL_MAP_L2_BASE + 3)
mov dword [abs VIRTUAL_MAP_BASE + 8], (VIRTUAL_MAP_L2_BASE + VIRTUAL_MAP_L2_SIZE + 3)

; Point the L2 entries to L1 entries
mov ecx, 1024                        ; There are 1024 entries, because each L3 has 512 entries
mov ebx, (VIRTUAL_MAP_L1_BASE + 3)   ; Add the 3, so that the page is present, readable and writable
mov edi, (VIRTUAL_MAP_L2_BASE)
page_map_virtual_mapping_L0:
mov dword [edi], ebx
add edi, 8
add ebx, 0x1000       ; Jump over 512 entries, because each L2 has 512 entries
dec ecx
jnz page_map_virtual_mapping_L0

; Point the L1 entries to the page map
mov ecx, 524288                        ; There are 524288 entries, because there are 1024 L2 entries and each has 512 entries
mov ebx, (PAGE_MAP_BASE + 3)           ; Add the 3, so that the page is present, readable and writable
mov edi, (VIRTUAL_MAP_L1_BASE)         ; Start after the last L2
page_map_virtual_mapping_L1:
mov dword [edi], ebx
add edi, 8
add ebx, 0x1000
dec ecx
jnz page_map_virtual_mapping_L1

; Point the last entry of the page map to the virtual mapping, so that we can edit the page map later using virtual addresses
mov dword [abs (PAGE_MAP_BASE + 511 * 8)], (VIRTUAL_MAP_BASE + 3)

; Map the first 4MB
mov dword [abs L4_BASE], (L3_BASE + 3)
mov dword [abs L3_BASE], (L2_BASE + 3)
mov dword [abs L2_BASE], (L1_BASE + 3)

; Flag the pages present, readable and writable (111b)
mov edi, L1_BASE
mov ebx, 3
mov ecx, 512
initial_map_L0:
mov dword [edi], ebx
add ebx, 0x1000
add edi, 8
dec ecx
jnz initial_map_L0

; Start enabling the long mode:

; Register the page map
mov edi, PAGE_MAP_BASE
mov cr3, edi

; Enable PAE-paging
mov eax, cr4
or eax, 1 << 5
mov cr4, eax

; Enable long mode
mov ecx, 0xC0000080
rdmsr
or eax, (1 << 8)
wrmsr

; Enable paging
mov eax, cr0
or eax, (1 << 31) | (1 << 0)
mov cr0, eax

; Load the 64-bit global descriptor table
lgdt [gdt64_descriptor]
jmp CODE_SEGMENT_64:enter_kernel

[bits 64]
enter_kernel:
mov ax, DATA_SEGMENT_64
mov ds, ax
mov ss, ax
mov es, ax
mov fs, ax
mov gs, ax

mov edi, dword [multiboot_information]
jmp kernel_entry

; ########################################################################################

gdt32_start:
dq 0x0 ; None segment descriptor

; Code segment descriptor
gdt32_code:
dw 0xffff    ; Segment length, bits 0-15
dw 0x0       ; Segment base, bits 0-15
db 0x0       ; Segment base, bits 16-23
db 10011010b ; Flags (8 bits)
db 11001111b ; Flags (4 bits) + segment length, bits 16-19
db 0x0       ; Segment base, bits 24-31

; Data segment descriptor
gdt32_data:
dw 0xffff    ; Segment length, bits 0-15
dw 0x0       ; Segment base, bits 0-15
db 0x0       ; Segment base, bits 16-23
db 10010010b ; Flags (8 bits)
db 11001111b ; Flags (4 bits) + segment length, bits 16-19
db 0x0       ; Segment base, bits 24-31

gdt32_end:

gdt32_descriptor:
dw gdt32_end - gdt32_start - 1
dd gdt32_start

; ########################################################################################

align 8
gdt64_start:

; Null descriptor
dw      0x0000
dw      0x0000
db      0x00
db      0x00
db      0x00
db      0x00

; kernel: code segment descriptor (selector = 0x10)
gdt64_code:
dw      0x0000
dw      0x0000
db      0x00
db      10011010b
db      00100000b
db      0x00

; kernel: data segment descriptor (selector = 0x08)
gdt64_data:
dw      0x0000
dw      0x0000
db      0x00
db      10010010b
db      00000000b
db      0x00

; user: code segment descriptor (selector = 0x20)
dw      0x0000
dw      0x0000
db      0x00
db      11111010b
db      00100000b
db      0x00

; user: data segment descriptor (selector = 0x18)
dw      0x0000
dw      0x0000
db      0x00
db      11110010b
db      00000000b
db      0x00

dd 0x00000068
dd 0x00CF8900

gdt64_end:

align 8

gdt64_descriptor:
dw gdt64_end - gdt64_start - 1
dd gdt64_start

; ########################################################################################

multiboot_information:
dd 0

CODE_SEGMENT_32    equ gdt32_code - gdt32_start
DATA_SEGMENT_32    equ gdt32_data - gdt32_start

CODE_SEGMENT_64    equ gdt64_code - gdt64_start
DATA_SEGMENT_64    equ gdt64_data - gdt64_start

MAX_MEMORY equ 2000000000 ; 2 GB
L1_COUNT   equ 488448
L2_COUNT   equ 1024
L3_COUNT   equ 512
L4_COUNT   equ 512

align 0x2000
kernel_entry:

incbin "build/kernel.bin"

kernel_end: