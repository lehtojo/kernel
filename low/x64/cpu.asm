.intel_syntax noprefix
.global read_msr
read_msr:
mov rcx, rdi
rdmsr
sal rdx, 32
or rax, rdx
ret

.global write_msr
write_msr:
mov rcx, rdi
mov rax, rsi
mov rdx, rsi
shr rdx, 32
wrmsr
ret

.global write_cr0
write_cr0:
mov cr0, rdi
ret

.global write_cr1
write_cr1:
mov cr1, rdi
ret

.global write_cr2
write_cr2:
mov cr2, rdi
ret

.global write_cr3
write_cr3:
mov cr3, rdi
ret

.global write_cr4
write_cr4:
mov cr4, rdi
ret

.global read_cr0
read_cr0:
mov rax, cr0
ret

.global read_cr1
read_cr1:
mov rax, cr1
ret

.global read_cr2
read_cr2:
mov rax, cr2
ret

.global read_cr3
read_cr3:
mov rax, cr3
ret

.global read_cr4
read_cr4:
mov rax, cr4
ret

.global write_gdtr
write_gdtr:
lgdt [rdi]
ret

.global write_fs_base
write_fs_base:
wrfsbase rdi
ret

.global read_fs_base
read_fs_base:
rdfsbase rax
ret

.global flush_tlb_local
flush_tlb_local:
invlpg [rdi]
ret

.global flush_tlb
flush_tlb:
mov rax, cr3
mov cr3, rax
ret

.global interrupts_enable
interrupts_enable:
sti
ret

.global interrupts_disable
interrupts_disable:
sti
ret

.global interrupts_set_idtr
interrupts_set_idtr:
lidt [rdi]
ret

.global ports_read_u8
ports_read_u8:
xor rax, rax
mov rdx, rdi
in al, dx
ret

.global ports_read_u16
ports_read_u16:
xor rax, rax
mov rdx, rdi
in ax, dx
ret

.global ports_read_u32
ports_read_u32:
xor rax, rax
mov rdx, rdi
in eax, dx
ret


.global ports_write_u8
ports_write_u8:
mov rax, rsi
mov rdx, rdi
out dx, al
ret

.global ports_write_u16
ports_write_u16:
mov rax, rsi
mov rdx, rdi
out dx, ax
ret

.global ports_write_u32
ports_write_u32:
mov rax, rsi
mov rdx, rdi
out dx, eax
ret

.global registers_rsp
registers_rsp:
lea rax, [rsp+8]
ret

.global registers_rip
registers_rip:
mov rax, [rsp]
ret

.align 32
.global interrupt_entry
interrupt_entry:
# Todo: Move cli instruction to interrupt entry before this, so that interrupts are immediately disabled, so that nothing gets pushed to stack before disabling
cli # Disable interrupts

# Save the interrupt stack pointer and load the kernel stack pointer
# Note: Each thread has its own kernel stack for saving the state in kernel easily
mov [gs:0], rsp
mov rsp, [gs:8]

# Interrupt stack has data we do not have in this new stack, reserve space for it and copy it later
sub rsp, 56

# Save all the registers
push r15
push r14
push r13
push r12
push r11
push r10
push r9
push r8
push rax
push rcx
push rdx
push rbx
push rsp
push rbp
push rsi
push rdi

# Copy the data pushed in the interrupt stack to the allocated region
lea rdi, [rsp+128]
mov rsi, [gs:0]
mov rcx, 7
rep movsq

mov rdi, rsp # Pass the register state
call _VN6kernel10interrupts7processEPP13RegisterState_ry

# If the return address (rip) is in kernel mode, do a kernel switch
mov rdi, [rsp+144]
test rdi, rdi
jl kernel_switch_return

# Copy changes to the interrupt stack
lea rsi, [rsp+128]
mov rdi, [gs:24]
sub rdi, 56 # 7 * 8
mov rcx, 7
rep movsq

pop rdi
pop rsi
pop rbp
add rsp, 8 # Skip restoring rsp
pop rbx
pop rdx
pop rcx
pop rax
pop r8
pop r9
pop r10
pop r11
pop r12
pop r13
pop r14
pop r15

# Switch back to the interrupt stack
mov rsp, [gs:24]
sub rsp, 56

add rsp, 16 # Remove the interrupt number and padding (Added by the interrupt entry)

iretq # Note: Interrupts are enabled by restoring rflags

.global system_call_entry
system_call_entry:
# Interrupts are disabled

# Save the user stack pointer and load the kernel stack pointer
mov [gs:0], rsp
mov rsp, [gs:8]

pushq 0x1b # User ss (0x18 | 3)
pushq [gs:0] # User rsp

push r11 # RFLAGS
pushq 0x23 # User cs (0x20 | 3)
push rcx # User RIP
pushq 0 # Padding
pushq 0x80 # "System call interrupt"

push r15
push r14
push r13
push r12
push r11
push r10
push r9
push r8
push rax
push rcx
push rdx
push rbx
push rsp
push rbp
push rsi
push rdi

mov rdi, rsp
call _VN6kernel10interrupts7processEPP13RegisterState_ry

# If the return address (rip) is in kernel mode, do a kernel switch
mov rdi, [rsp+144]
test rdi, rdi
jl kernel_switch_return

pop rdi
pop rsi
pop rbp
add rsp, 8 # Skip restoring rsp
pop rbx
pop rdx
pop rcx
add rsp, 8 # Skip restoring rax
pop r8
pop r9
pop r10
pop r11
pop r12
pop r13
pop r14
pop r15

add rsp, 16 # Remove the interrupt number and padding
pop rcx
add rsp, 8
pop r11 # Load rflags

pop rsp
sysretq # Enables interrupts

kernel_switch_return:
pop rdi
pop rsi
pop rbp
add rsp, 8 # Skip restoring rsp
pop rbx
pop rdx
pop rcx
pop rax
pop r8
pop r9
pop r10
pop r11
pop r12
pop r13
pop r14
pop r15

# Note: Kernel switches are done using syscall instruction, so we have rcx and r11 to work with

add rsp, 16 # Remove the interrupt number and padding
popq [gs:0] # Save rip temporarily
add rsp, 8  # Do not restore cs as it is correct already
popfq       # Load rflags
pop rsp     # Load the stack pointer
jmp [gs:0]

.global get_interrupt_handler
get_interrupt_handler:
lea rax, [rip+interrupt_entry]
ret

.global get_system_call_handler
get_system_call_handler:
lea rax, [rip+system_call_entry]
ret

.global full_memory_barrier
full_memory_barrier:
lock or dword ptr [rsp], 0 # Note: Or zero with return address, does locking but nothing else
mfence
ret

.global wait_for_microseconds
wait_for_microseconds:
xor rax, rax
test rdi, rdi
jnz wait_for_microseconds_L0
ret
wait_for_microseconds_L0:
out 0x80, al
dec rdi
jnz wait_for_microseconds_L0
ret

.global system_call
system_call:
mov rax, rdi
mov rdi, rsi
mov rsi, rdx
mov rdx, rcx
mov r10, r8
mov r8, r9
mov r9, qword [rsp+8]
syscall
ret

.global save_fpu_state_xsave
save_fpu_state_xsave:
; mov rax, rsi
; mov rdx, rsi
; shr rdx, 32
fxsave [rdi]
ret

.global load_fpu_state_xrstor
load_fpu_state_xrstor:
; mov rax, rsi
; mov rdx, rsi
; shr rdx, 32
fxrstor [rdi]
ret

.global uefi_call_wrapper
uefi_call_wrapper:
sub rsp, 40 # Allocate memory for the shadow space and the last argument

# Convert between the following calling conventions:
# Note: RDI has the function pointer
# Arguments:               rsi, rdx, rcx, r8, r9
# UEFI calling convention: rcx, rdx, r8,  r9, [rsp+32]
mov qword ptr [rsp+32], r9
mov r9, r8
mov r8, rcx
# mov rdx, rdx
mov rcx, rsi

# Call the uefi function pointer
call rdi

add rsp, 40 # Remove the shadow space and the last argument
ret

# Todo: Prettify
.global forward_copy
forward_copy:
        test    rdx, rdx
        je      .LBB0_13
        cmp     rdx, 8
        jae     .LBB0_3
        xor     eax, eax
        jmp     .LBB0_12
.LBB0_3:
        cmp     rdx, 32
        jae     .LBB0_5
        xor     eax, eax
        jmp     .LBB0_9
.LBB0_5:
        mov     rax, rdx
        and     rax, -32
        xor     ecx, ecx
.LBB0_6:
        movups  xmm0, xmmword ptr [rsi + rcx]
        movups  xmm1, xmmword ptr [rsi + rcx + 16]
        movups  xmmword ptr [rdi + rcx], xmm0
        movups  xmmword ptr [rdi + rcx + 16], xmm1
        add     rcx, 32
        cmp     rax, rcx
        jne     .LBB0_6
        cmp     rax, rdx
        je      .LBB0_13
        test    dl, 24
        je      .LBB0_12
.LBB0_9:
        mov     rcx, rax
        mov     rax, rdx
        and     rax, -8
.LBB0_10:
        mov     r8, qword ptr [rsi + rcx]
        mov     qword ptr [rdi + rcx], r8
        add     rcx, 8
        cmp     rax, rcx
        jne     .LBB0_10
        cmp     rax, rdx
        je      .LBB0_13
.LBB0_12:
        movzx   ecx, byte ptr [rsi + rax]
        mov     byte ptr [rdi + rax], cl
        inc     rax
        cmp     rdx, rax
        jne     .LBB0_12
.LBB0_13:
        ret

.global reverse_copy
reverse_copy:
        test    rdx, rdx
        je      .LBB1_11
        cmp     rdx, 4
        jae     .LBB1_4
        xor     eax, eax
.LBB1_3:
        mov     rcx, rdi
        mov     r8, rsi
        jmp     .LBB1_9
.LBB1_4:
        cmp     rdx, 16
        jae     .LBB1_12
        xor     eax, eax
        jmp     .LBB1_6
.LBB1_12:
        mov     rax, rdx
        and     rax, -16
        mov     rcx, rax
        neg     rcx
        xor     r8d, r8d
.LBB1_13:
        movups  xmm0, xmmword ptr [rsi + r8 - 15]
        movups  xmmword ptr [rdi + r8 - 15], xmm0
        add     r8, -16
        cmp     rcx, r8
        jne     .LBB1_13
        cmp     rax, rdx
        je      .LBB1_11
        test    dl, 12
        je      .LBB1_16
.LBB1_6:
        mov     r9, rax
        mov     rax, rdx
        and     rax, -4
        mov     r10, rax
        neg     r10
        mov     rcx, rdi
        sub     rcx, rax
        mov     r8, rsi
        sub     r8, rax
        neg     r9
.LBB1_7: 
        mov     r11d, dword ptr [rsi + r9 - 3]
        mov     dword ptr [rdi + r9 - 3], r11d
        add     r9, -4
        cmp     r10, r9
        jne     .LBB1_7
        cmp     rax, rdx
        je      .LBB1_11
.LBB1_9:
        sub     rax, rdx
        xor     edx, edx
.LBB1_10:
        movzx   esi, byte ptr [r8 + rdx]
        mov     byte ptr [rcx + rdx], sil
        dec     rdx
        cmp     rax, rdx
        jne     .LBB1_10
.LBB1_11:
        ret
.LBB1_16:
        sub     rsi, rax
        sub     rdi, rax
        jmp     .LBB1_3

.global zero
zero:
        test    rsi, rsi
        je      .LBB2_8
        cmp     rsi, 8
        jae     .LBB2_3
        xor     eax, eax
.LBB2_14:
        mov     rcx, rdi
        jmp     .LBB2_15
.LBB2_3:
        cmp     rsi, 32
        jae     .LBB2_9
        xor     eax, eax
        jmp     .LBB2_5
.LBB2_9:
        mov     rax, rsi
        and     rax, -32
        xor     ecx, ecx
        xorps   xmm0, xmm0
.LBB2_10:
        movups  xmmword ptr [rdi + rcx], xmm0
        movups  xmmword ptr [rdi + rcx + 16], xmm0
        add     rcx, 32
        cmp     rax, rcx
        jne     .LBB2_10
        cmp     rax, rsi
        je      .LBB2_8
        test    sil, 24
        je      .LBB2_13
.LBB2_5:
        mov     rdx, rax
        mov     rax, rsi
        and     rax, -8
        lea     rcx, [rdi + rax]
.LBB2_6:
        mov     qword ptr [rdi + rdx], 0
        add     rdx, 8
        cmp     rax, rdx
        jne     .LBB2_6
        cmp     rax, rsi
        je      .LBB2_8
.LBB2_15:
        sub     rsi, rax
        xor     eax, eax
.LBB2_16:
        mov     byte ptr [rcx + rax], 0
        inc     rax
        cmp     rsi, rax
        jne     .LBB2_16
.LBB2_8:
        ret
.LBB2_13:
        add     rdi, rax
        jmp     .LBB2_14

# void color_area(unsigned int* pixels, unsigned int width, unsigned int height, unsigned int stride, unsigned int foreground, unsigned int background) {
#     unsigned char fr = (foreground >> 16) & 0xFF;
#     unsigned char fg = (foreground >> 8) & 0xFF;
#     unsigned char fb = foreground & 0xFF;
# 
#     unsigned char br = (background >> 16) & 0xFF;
#     unsigned char bg = (background >> 8) & 0xFF;
#     unsigned char bb = background & 0xFF;
# 
#     for (unsigned int y = 0; y < height; y++) {
#         for (unsigned int i = 0; i < width; i++) {
#             unsigned char intensity = pixels[i];
# 
#             unsigned char rr = ((unsigned short)fr * intensity + (unsigned short)br * (255 - intensity)) / 255;
#             unsigned char rg = ((unsigned short)fg * intensity + (unsigned short)bg * (255 - intensity)) / 255;
#             unsigned char rb = ((unsigned short)fb * intensity + (unsigned short)bb * (255 - intensity)) / 255;
# 
#             pixels[i] = (rr << 16) | (rg << 8) | rb;
#         }
# 
#         pixels += stride / sizeof(unsigned int);
#     }
# }
.global color_area
color_area:
  push r15
  mov eax, r9d
  push r14
  shr eax, 16
  push r13
  mov r13d, r8d
  push r12
  mov r12d, r8d
  shr r13d, 16
  push rbp
  shr r12d, 8
  push rbx
  mov ebx, esi
  mov esi, edx
  sub rsp, 64
  mov DWORD PTR [rsp+28], edx
  mov edx, eax
  mov eax, r9d
  shr eax, 8
  test esi, esi
  je .L1
  mov esi, ecx
  and esi, -4
  mov QWORD PTR [rsp+32], rsi
  test ebx, ebx
  je .L1
  lea esi, [rbx-1]
  movzx r13d, r13b
  movzx eax, al
  mov ecx, ebx
  mov DWORD PTR [rsp+48], esi
  mov esi, ebx
  movd xmm7, r13d
  movd xmm0, eax
  and esi, -4
  pshufd xmm7, xmm7, 0
  shr ecx, 2
  mov DWORD PTR [rsp+24], eax
  mov DWORD PTR [rsp+52], esi
  movzx esi, dl
  pshufd xmm0, xmm0, 0
  sal rcx, 4
  movaps XMMWORD PTR [rsp-88], xmm7
  movd xmm2, esi
  psrlq xmm7, 32
  xor ebp, ebp
  mov DWORD PTR [rsp+20], esi
  movzx r12d, r12b
  movzx r8d, r8b
  movzx r9d, r9b
  pshufd xmm2, xmm2, 0
  movaps XMMWORD PTR [rsp-40], xmm7
  movdqa xmm7, xmm2
  movdqa xmm14, XMMWORD PTR .LC0[rip]
  psrlq xmm7, 32
  movaps XMMWORD PTR [rsp-72], xmm2
  movdqa xmm2, XMMWORD PTR .LC1[rip]
  movaps XMMWORD PTR [rsp-24], xmm7
  movdqa xmm7, xmm0
  psrlq xmm7, 32
  mov QWORD PTR [rsp+40], rcx
  movaps XMMWORD PTR [rsp-8], xmm7
  pxor xmm7, xmm7
  movdqa xmm13, xmm7
  movaps XMMWORD PTR [rsp-56], xmm0
  pcmpgtd xmm13, xmm2
.L4:
  cmp DWORD PTR [rsp+48], 2
  jbe .L24
  movd xmm0, r12d
  mov rsi, QWORD PTR [rsp+40]
  mov rax, rdi
  pshufd xmm12, xmm0, 0
  movd xmm0, r8d
  movdqa xmm15, xmm12
  pshufd xmm11, xmm0, 0
  movd xmm0, r9d
  lea rdx, [rdi+rsi]
  pshufd xmm10, xmm0, 0
  movdqa xmm0, xmm11
  psrlq xmm15, 32
  psrlq xmm0, 32
  movaps XMMWORD PTR [rsp-120], xmm0
  movdqa xmm0, xmm10
  psrlq xmm0, 32
  movaps XMMWORD PTR [rsp-104], xmm0
.L5:
  movdqu xmm1, XMMWORD PTR [rax]
  movdqa xmm9, xmm15
  add rax, 16
  movdqa xmm4, XMMWORD PTR [rsp-88]
  movdqa xmm3, XMMWORD PTR [rsp-40]
  movdqa xmm8, XMMWORD PTR [rsp-24]
  movdqa xmm0, xmm1
  pandn xmm1, xmm14
  pand xmm0, xmm14
  movdqa xmm5, xmm1
  pmuludq xmm4, xmm0
  psrlq xmm5, 32
  movdqa xmm6, xmm0
  psrlq xmm6, 32
  pmuludq xmm8, xmm5
  pmuludq xmm3, xmm6
  pmuludq xmm9, xmm6
  pmuludq xmm6, XMMWORD PTR [rsp-120]
  pshufd xmm6, xmm6, 8
  pshufd xmm4, xmm4, 8
  pshufd xmm8, xmm8, 8
  pshufd xmm3, xmm3, 8
  pshufd xmm9, xmm9, 8
  punpckldq xmm4, xmm3
  movdqa xmm3, XMMWORD PTR [rsp-72]
  pmuludq xmm3, xmm1
  pshufd xmm3, xmm3, 8
  punpckldq xmm3, xmm8
  movdqa xmm8, XMMWORD PTR [rsp-56]
  paddd xmm4, xmm3
  movdqa xmm3, XMMWORD PTR [rsp-8]
  pmuludq xmm8, xmm1
  pmuludq xmm1, xmm10
  pmuludq xmm3, xmm5
  pmuludq xmm5, XMMWORD PTR [rsp-104]
  pshufd xmm5, xmm5, 8
  pshufd xmm8, xmm8, 8
  pshufd xmm1, xmm1, 8
  pshufd xmm3, xmm3, 8
  punpckldq xmm1, xmm5
  movdqa xmm5, xmm4
  punpckldq xmm8, xmm3
  pmuludq xmm5, xmm2
  movdqa xmm3, xmm12
  pmuludq xmm3, xmm0
  pmuludq xmm0, xmm11
  pshufd xmm0, xmm0, 8
  pshufd xmm3, xmm3, 8
  punpckldq xmm0, xmm6
  movdqa xmm6, xmm13
  punpckldq xmm3, xmm9
  paddd xmm0, xmm1
  movdqa xmm1, xmm7
  paddd xmm3, xmm8
  pcmpgtd xmm1, xmm4
  pmuludq xmm6, xmm4
  movdqa xmm8, xmm13
  pmuludq xmm1, xmm2
  paddq xmm1, xmm6
  movdqa xmm6, xmm7
  psllq xmm1, 32
  paddq xmm5, xmm1
  movdqa xmm1, xmm4
  psrlq xmm1, 32
  pcmpgtd xmm6, xmm1
  pmuludq xmm8, xmm1
  pmuludq xmm1, xmm2
  pmuludq xmm6, xmm2
  paddq xmm6, xmm8
  movdqa xmm8, xmm13
  psllq xmm6, 32
  paddq xmm1, xmm6
  movdqa xmm6, xmm13
  shufps xmm5, xmm1, 221
  movdqa xmm1, xmm7
  pmuludq xmm6, xmm3
  pshufd xmm5, xmm5, 216
  pcmpgtd xmm1, xmm3
  paddd xmm5, xmm4
  movdqa xmm4, xmm3
  pmuludq xmm4, xmm2
  psrad xmm5, 7
  pslld xmm5, 16
  pmuludq xmm1, xmm2
  paddq xmm1, xmm6
  movdqa xmm6, xmm7
  psllq xmm1, 32
  paddq xmm4, xmm1
  movdqa xmm1, xmm3
  psrlq xmm1, 32
  pcmpgtd xmm6, xmm1
  pmuludq xmm8, xmm1
  pmuludq xmm1, xmm2
  pmuludq xmm6, xmm2
  paddq xmm6, xmm8
  psllq xmm6, 32
  paddq xmm1, xmm6
  movdqa xmm6, xmm13
  shufps xmm4, xmm1, 221
  pshufd xmm4, xmm4, 216
  movdqa xmm1, xmm0
  paddd xmm4, xmm3
  pmuludq xmm1, xmm2
  movdqa xmm3, xmm7
  pcmpgtd xmm3, xmm0
  psrad xmm4, 7
  pslld xmm4, 8
  por xmm4, xmm5
  movdqa xmm5, xmm13
  pmuludq xmm5, xmm0
  pmuludq xmm3, xmm2
  paddq xmm3, xmm5
  movdqa xmm5, xmm7
  psllq xmm3, 32
  paddq xmm1, xmm3
  movdqa xmm3, xmm0
  psrlq xmm3, 32
  pcmpgtd xmm5, xmm3
  pmuludq xmm6, xmm3
  pmuludq xmm3, xmm2
  pmuludq xmm5, xmm2
  paddq xmm5, xmm6
  psllq xmm5, 32
  paddq xmm3, xmm5
  shufps xmm1, xmm3, 221
  pshufd xmm1, xmm1, 216
  paddd xmm1, xmm0
  psrad xmm1, 7
  por xmm4, xmm1
  movups XMMWORD PTR [rax-16], xmm4
  cmp rdx, rax
  jne .L5
  test bl, 3
  je .L6
  mov r11d, DWORD PTR [rsp+52]
.L7:
  mov eax, r11d
  mov ecx, DWORD PTR [rsp+20]
  mov r15d, DWORD PTR [rsp+24]
  mov r10d, 2155905153
  lea r14, [rdi+rax*4]
  mov esi, DWORD PTR [r14]
  movzx edx, sil
  not esi
  movzx esi, sil
  mov eax, edx
  imul ecx, esi
  imul eax, r13d
  imul r15d, esi
  imul esi, r9d
  add ecx, eax
  mov eax, edx
  imul eax, r12d
  imul edx, r8d
  imul rcx, r10
  add eax, r15d
  imul rax, r10
  add edx, esi
  imul rdx, r10
  shr rcx, 39
  sal ecx, 16
  shr rax, 39
  sal eax, 8
  shr rdx, 39
  or eax, ecx
  or eax, edx
  mov DWORD PTR [r14], eax
  lea eax, [r11+1]
  cmp eax, ebx
  jnb .L6
  lea r14, [rdi+rax*4]
  mov ecx, DWORD PTR [rsp+20]
  mov r15d, DWORD PTR [rsp+24]
  add r11d, 2
  mov esi, DWORD PTR [r14]
  movzx edx, sil
  not esi
  movzx esi, sil
  mov eax, edx
  imul eax, r13d
  imul ecx, esi
  imul r15d, esi
  imul esi, r9d
  add ecx, eax
  mov eax, edx
  imul eax, r12d
  imul edx, r8d
  imul rcx, r10
  add eax, r15d
  imul rax, r10
  add edx, esi
  imul rdx, r10
  shr rcx, 39
  sal ecx, 16
  shr rax, 39
  sal eax, 8
  shr rdx, 39
  or eax, ecx
  or eax, edx
  mov DWORD PTR [r14], eax
  cmp r11d, ebx
  jnb .L6
  lea r11, [rdi+r11*4]
  mov r15d, DWORD PTR [rsp+24]
  mov edx, DWORD PTR [rsp+20]
  mov eax, DWORD PTR [r11]
  movzx esi, al
  not eax
  mov r14d, esi
  movzx eax, al
  imul r14d, r12d
  imul r15d, eax
  imul edx, eax
  mov ecx, r14d
  imul eax, r9d
  mov r14d, esi
  imul r14d, r13d
  add ecx, r15d
  imul esi, r8d
  imul rcx, r10
  add edx, r14d
  imul rdx, r10
  add eax, esi
  imul rax, r10
  shr rcx, 39
  sal ecx, 8
  shr rdx, 39
  sal edx, 16
  shr rax, 39
  or edx, ecx
  or edx, eax
  mov DWORD PTR [r11], edx
.L6:
  mov rax, QWORD PTR [rsp+32]
  add ebp, 1
  add rdi, rax
  cmp DWORD PTR [rsp+28], ebp
  jne .L4
.L1:
  add rsp, 64
  pop rbx
  pop rbp
  pop r12
  pop r13
  pop r14
  pop r15
  ret
.L24:
  xor r11d, r11d
  jmp .L7
.LC0:
  .long 255
  .long 255
  .long 255
  .long 255
.LC1:
  .long -2139062143
  .long -2139062143
  .long -2139062143
  .long -2139062143
