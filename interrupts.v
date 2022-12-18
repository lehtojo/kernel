pack RegisterState {
	rdi: u64
	rsi: u64
	rbp: u64
	rsp: u64
	rbx: u64
	rdx: u64
	rcx: u64
	rax: u64
	r8: u64
	r9: u64
	r10: u64
	r11: u64
	r12: u64
	r13: u64
	r14: u64
	r15: u64
	interrupt: u64
	padding: u64
	rip: u64
	cs: u64
	rflags: u64
	userspace_rsp: u64
	userspace_ss: u64
}

pack TrapFrame {
	previous_interrupt_request_level: link
	next_trap: TrapFrame*
	registers: RegisterState*
}

namespace kernel.interrupts

namespace internal {
	import 'C' interrupts_set_idtr(idtr: link)
	import 'C' interrupts_enable()
	import 'C' interrupts_disable()

	import 'C' get_interrupt_handler(): link
}

constant IDTR_OFFSET = 0
constant IDT_OFFSET = 0x1000
constant INTERRUPT_ENTRIES_OFFSET = 0x2000
constant INTERRUPT_COUNT = 256

constant PRESENT_BIT = 1 <| 7

constant GATE_TYPE_INTERRUPT = 0xE
constant GATE_TYPE_TRAP = 0xF

tables: link
scheduler: kernel.scheduler.Scheduler

pack InterruptDescriptor {
	offset_1: u16
	selector: u16
	interrupt_stack_table_offset: u8
	type_attributes: u8
	offset_2: u16
	offset_3: u32
	reserved: u32
}

export initialize() {
	(tables + IDTR_OFFSET).(i16*)[] = INTERRUPT_COUNT * 16 - 1
	(tables + IDTR_OFFSET + 2).(link*)[] = tables + IDT_OFFSET

	memory.zero(tables + IDT_OFFSET as link, 0x1000)

	entry_address = tables + INTERRUPT_ENTRIES_OFFSET

	loop (i = 0, i < INTERRUPT_COUNT, i++) {
		if i < 0x20 {
			set_interrupt(i, 0, entry_address)
		} else {
			set_trap(i, 0, entry_address)
		}

		entry_address = write_interrupt_entry(entry_address, internal.get_interrupt_handler(), i)
	}

	internal.interrupts_set_idtr(tables + IDTR_OFFSET)
}

export enable() {
	internal.interrupts_enable()
}

export disable() {
	internal.interrupts_disable()
}

# Summary:
# Writes an interrupt entry to the specified address that pushes the interrupt number to stack and jumps to the handler.
# Returns the address after writing the entry.
export write_interrupt_entry(address: link, to: link, interrupt: i32) {
	# Align the stack to 16 bytes
	address[0] = 0x68 # push dword 0
	(address + 1).(i32*)[] = interrupt
	address += sizeof(i32) + 1

	# Push the interrupt number so that the handler knows which interrupt is being called
	address[0] = 0x68 # push dword interrupt
	(address + 1).(i32*)[] = interrupt
	address += sizeof(i32) + 1

	# Jump to the interrupt handler
	from = address + sizeof(i32) + 1
	offset = to - from

	address[0] = 0xe9 # jmp to
	(address + 1).(i32*)[] = offset
	address += sizeof(i32) + 1

	return address + 1 # Align to 16 bytes
}

export set_interrupt(index: u32, privilege: u8, handler: link) {
	# TODO: Add more checks
	privilege &= 3 # Take only the first two bits

	descriptor: InterruptDescriptor
	descriptor.offset_1 = (handler as u64)
	descriptor.selector = 8
	descriptor.interrupt_stack_table_offset = 1
	descriptor.type_attributes = PRESENT_BIT | (privilege <| 5) | GATE_TYPE_INTERRUPT
	descriptor.offset_2 = ((handler as u64) |> 16)
	descriptor.offset_3 = ((handler as u64) |> 32)
	descriptor.reserved = 0

	(tables + IDT_OFFSET).(InterruptDescriptor*)[index] = descriptor
}

export set_trap(index: u32, privilege: u8, handler: link) {
	# TODO: Add more checks
	privilege &= 3 # Take only the first two bits

	descriptor: InterruptDescriptor
	descriptor.offset_1 = (handler as u64)
	descriptor.selector = 8
	descriptor.interrupt_stack_table_offset = 1
	descriptor.type_attributes = PRESENT_BIT | (privilege <| 5) | GATE_TYPE_TRAP
	descriptor.offset_2 = ((handler as u64) |> 16)
	descriptor.offset_3 = ((handler as u64) |> 32)
	descriptor.reserved = 0

	(tables + IDT_OFFSET).(InterruptDescriptor*)[index] = descriptor
}

export process(frame: TrapFrame*) {
	code = frame[].registers[].interrupt

	if code == 0x21 {
		kernel.keyboard.process()
	} else code == 0x24 {
		scheduler.tick(frame)
	} else code == 0x0e {
		debug.write('Page fault at address ')
		debug.write_address(frame[].registers[].cs)
		debug.write_line()
		panic('Page fault')
	} else {
		default_handler()
	}

	interrupts.end()
}

export end() {
	# Send the end-of-interrupt signal
	# 8259 PIC: ports.write_u8(0x20, 0x20)
	(apic.local_apic_registers + 0xB0)[] = 0
}

export default_handler() {}