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

.global write_cr3
write_cr3:
mov cr3, rdi
ret

.global write_cr4
write_cr4:
mov cr4, rdi
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

.align 32
.global interrupt_entry
interrupt_entry:
cli # Disable interrupts

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

mov rax, rsp # Save the address of the register state
sub rsp, 24 # Reserve memory for a trap frame object

mov qword ptr [rsp], 0
mov qword ptr [rsp+8], 0
mov qword ptr [rsp+16], rax # Pass the register state

mov rdi, rsp
call _VN6kernel10interrupts7processEPP9TrapFrame_ry

add rsp, 24 # Remove the trap frame object and the padding

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

add rsp, 16 # Remove the interrupt number and padding (Added by the interrupt entry)

sti # Enable interrupts
iretq

.global system_call_entry
system_call_entry:
# Interrupts are disabled

# Save the user stack pointer and load the kernel stack pointer
mov qword [gs:16], rsp
mov rsp, [gs:8]

pushq 0x18 # User ss
push qword [gs:16] # User rsp

push r11 # RFLAGS
pushq 0x20 # User cs
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

mov rax, rsp # Save the address of the register state
sub rsp, 24 # Reserve memory for a trap frame object

mov qword ptr [rsp], 0
mov qword ptr [rsp+8], 0
mov qword ptr [rsp+16], rax # Pass the register state

mov rdi, rsp
call _VN6kernel10interrupts7processEPP9TrapFrame_ry

add rsp, 24 # Remove the trap frame object and the padding

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
add rsp, 16

pop rsp
sysretq # Enables interrupts

.global get_interrupt_handler
get_interrupt_handler:
lea rax, [rip+interrupt_entry]
ret

.global get_system_call_handler
get_system_call_handler:
lea rax, [rip+system_call_entry]
ret
