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
mov [gs:16], rsp
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
mov rsi, [gs:16]
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
mov rdi, [gs:16]
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
mov rsp, [gs:16]

add rsp, 16 # Remove the interrupt number and padding (Added by the interrupt entry)

iretq # Note: Interrupts are enabled by restoring rflags

.global system_call_entry
system_call_entry:
# Interrupts are disabled

# Save the user stack pointer and load the kernel stack pointer
mov [gs:16], rsp
mov rsp, [gs:8]

pushq 0x1b # User ss (0x18 | 3)
pushq [gs:16] # User rsp

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
add rsp, 8 # Skip restoring rax
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
pop rcx     # Load rip
add rsp, 8  # Do not restore cs as it is correct already
popfq       # Load rflags
pop rsp     # Load the stack pointer
jmp rcx

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
