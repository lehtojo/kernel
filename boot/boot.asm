[bits 32]
global start
start:

; Disable interrupts
cli

; Verify the boot was done using the multiboot protocol
cmp eax, 0x36d76289
je multiboot_verified
hlt
multiboot_verified:

; Save the boot information provided by the multiboot protocol
mov dword [multiboot_information], ebx

; Register the global descriptor table
lgdt [gdt32_descriptor]

; Initialize segments
mov ax, DATA_SEGMENT_32
mov ds, ax
mov ss, ax
mov es, ax
mov fs, ax
mov gs, ax

; Setup the stack
mov ebp, kernel_stack_start
mov esp, ebp

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

; VIRTUAL_MAP_BASE      VIRTUAL_MAP_L2_BASE   VIRTUAL_MAP_L1_BASE   PAGE_MAP_BASE     L3_BASE           L2_BASE           L1_BASE           PAGE_MAP_END
; v                     v                     v                     v                 v                 v                 v                 v
; -------------------------------------------------------------------------------------------------------------------------------------------
; | VIRTUAL_MAP_L3_BASE | VIRTUAL_MAP_L2_BASE | VIRTUAL_MAP_L1_BASE |     L4_BASE  [ ]|     L3_BASE     |     L2_BASE     |     L1_BASE     |
; -------------------------------------------------------------------------------------------------------------------------------------------
;           ^ |-------------------^ |-------------------^ |-------------------------|----------------------------------------------^
;           |                                                                       |
;           -------------------------------------------------------------------------

; Zero out the page tables
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
mov dword [abs (L4_BASE + 511 * 8)], (VIRTUAL_MAP_L3_BASE + 3)

; Identity map the first 1 GiB
mov dword [abs L4_BASE], (L3_BASE + 3)
mov dword [abs L3_BASE], (L2_BASE + 3)

; Initialize L2
mov edi, L2_BASE
mov ebx, (L1_BASE + 3) ; Present | Writable
mov ecx, 512
l2_mapper:
mov dword [edi], ebx
add ebx, 0x1000
add edi, 8
dec ecx
jnz l2_mapper

; Initialize L1
mov edi, L1_BASE
mov ebx, 3 ; Present | Writable
mov ecx, (512*512)
l1_mapper:
mov dword [edi], ebx
add ebx, 0x1000
add edi, 8
dec ecx
jnz l1_mapper

; Start enabling the long mode:

; Register the page map
mov edi, PAGE_MAP_BASE
mov cr3, edi

; Enable PAE-paging
mov eax, cr4
or eax, (1 << 5)
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

; Insert address of TSS into GDT before loading it
lea eax, [tss64]
mov word [gdt64_tss_address_0], ax
shr eax, 16
mov byte [gdt64_tss_address_1], al
shr eax, 8
mov byte [gdt64_tss_address_2], al

; Load the 64-bit global descriptor table
lgdt [gdt64_descriptor]

jmp CODE_SEGMENT_64:enter_kernel

[bits 64]
enter_kernel:
; Initialize segments
mov ax, DATA_SEGMENT_64
mov ds, ax
mov ss, ax
mov es, ax
mov fs, ax
mov gs, ax

; Register TSS from GDT
mov ax, TSS_SELECTOR
ltr ax

; Pass the multiboot information to the kernel
mov edi, dword [multiboot_information]
lea rsi, [abs interrupt_tables]
jmp kernel_entry

; --- GDT (32-bit) ---

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

align 8
gdt32_descriptor:
dw gdt32_end - gdt32_start - 1
dd gdt32_start

; --- GDT (64-bit) ---

align 8
gdt64_start:

; Null descriptor
dw      0x0000
dw      0x0000
db      0x00
db      0x00
db      0x00
db      0x00

; Kernel code segment (selector = 0x8)
gdt64_code:
dw      0x0000
dw      0x0000
db      0x00
db      10011010b
db      00100000b
db      0x00

; Kernel data segment (selector = 0x10)
gdt64_data:
dw      0x0000
dw      0x0000
db      0x00
db      10010010b
db      00000000b
db      0x00

; User code segment (selector = 0x18)
dw      0x0000
dw      0x0000
db      0x00
db      11111010b
db      00100000b
db      0x00

; User data segment (selector = 0x20)
dw      0x0000
dw      0x0000
db      0x00
db      11110010b
db      00000000b
db      0x00

; TSS segment (selector = 0x28)
gdt64_tss:
dw      0x0068
gdt64_tss_address_0:
dw      0x0000    ; TSS address (bits 0-16)
gdt64_tss_address_1:
db      0x00      ; TSS address (bits 16-24)
db      10001001b ; Present | 64-bit TSS (Available)
db      00000000b
gdt64_tss_address_2:
db      0x00      ; TSS address (bits 24-32)
dq      0x00      ; TSS address (bits 32-64)

gdt64_end:

align 8
gdt64_descriptor:
dw gdt64_end - gdt64_start - 1
dd gdt64_start

; --- TSS (64-bit) ---

align 8
tss64:
dd 0 ; reserved
dq interrupt_stack_start ; rsp0
dq 0 ; rsp1
dq 0 ; rsp2
dq 0 ; reserved
dq interrupt_stack_start ; ist1
dq 0 ; ist2
dq 0 ; ist3
dq 0 ; ist4
dq 0 ; ist5
dq 0 ; ist6
dq 0 ; ist7
dq 0 ; reserved
dw 0 ; reserved
dw 104 ; iopb

; --- Multiboot information ---

multiboot_information:
dd 0

; --- Configuration ---

CODE_SEGMENT_32 equ gdt32_code - gdt32_start
DATA_SEGMENT_32 equ gdt32_data - gdt32_start

CODE_SEGMENT_64 equ gdt64_code - gdt64_start
DATA_SEGMENT_64 equ gdt64_data - gdt64_start

TSS_SELECTOR equ gdt64_tss - gdt64_start

MAX_MEMORY equ 0x2000000000 ; 128 GB
L1_COUNT equ (MAX_MEMORY / 0x1000)
L2_COUNT equ (MAX_MEMORY / (0x1000 * 512))
L3_COUNT equ 512
L4_COUNT equ 512

; --- Kernel ---

align 0x2000
kernel_entry:

incbin "build/kernel.bin"

application_start:
incbin "hello"
application_end:

section .bss
align 0x1000

interrupt_tables:
resb 0x1000 ; interrupt descriptor table descriptor (idtr)
resb 0x1000 ; interrupt descriptor table (idt)
resb 0x1000 ; interrupt entries

resb 0x25000
interrupt_stack_start:

resb 0x25000
kernel_stack_start: