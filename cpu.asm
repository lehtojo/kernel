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


.align 32
.global old_keyboard_handler
old_keyboard_handler:
push rax
mov byte ptr [0xB8000], 48
mov byte ptr [0xB8001], 48
mov byte ptr [0xB8002], 48
mov al, 0x20
out 0x20, al
pop rax
iretq

.align 32
.global interrupt_entry
interrupt_entry:
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
call _VN10interrupts7processEPP9TrapFrame

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
iretq

.global get_interrupt_handler
get_interrupt_handler:
lea rax, [interrupt_entry]
ret

.global keyboard_handler
keyboard_handler:
lea rax, [_VN6kernel8keyboard7processEv]
ret

irq_enable:

    # Move IRQ into cl.
    mov     rcx,    rdi

    # Determine which PIC to update (<8 = master, else slave).
    cmp     cl,     8
    jae     irq_enable_slave

    irq_enable_master:

        # Compute the mask ~(1 << IRQ).
        mov     edx,    1
        shl     edx,    cl
        not     edx

        # Read the current mask.
        in      al,     0x21

        # Clear the IRQ bit and update the mask.
        and     al,     dl
        out     0x21,   al

        ret

    irq_enable_slave:

        # Recursively enable master IRQ2, or else slave IRQs will not work.
        mov     rdi,    2
        call    irq_enable

        # Subtract 8 from the IRQ.
        sub     cl,     8

        # Compute the mask ~(1 << IRQ).
        mov     edx,    1
        shl     edx,    cl
        not     edx

        # Read the current mask.
        in      al,     0xa1

        # Clear the IRQ bit and update the mask.
        and     al,     dl
        out     0xa1,   al

        ret

# idt = 0x9000
# idtr = 0x8000

.global test_interrupt
test_interrupt:
# Initialize the master PIC.
mov     al,     0x11        # ICW1: 0x11 = init with 4 ICW's
out     0x20,   al
mov     al,     0x20        # ICW2: 0x20 = interrupt offset 32
out     0x21,   al
mov     al,     0x04        # ICW3: 0x04 = IRQ2 has a slave
out     0x21,   al
mov     al,     0x01        # ICW4: 0x01 = x86 mode
out     0x21,   al

# Initialize the slave PIC.
mov     al,     0x11        # ICW1: 0x11 = init with 4 ICW's
out     0xa0,   al
mov     al,     0x28        # ICW2: 0x28 = interrupt offset 40
out     0xa1,   al
mov     al,     0x02        # ICW3: 0x02 = attached to master IRQ2.
out     0xa1,   al
mov     al,     0x01        # ICW4: 0x01 = x86 mode
out     0xa1,   al

# Disable all IRQs. The kernel will re-enable the ones it wants to
# handle later.
mov     al,     0xff
out     0x21,   al
out     0xa1,   al

# Register an empty interrupt descriptor table
lidt [0x8000]

mov rdi, 1
call irq_enable

ret
