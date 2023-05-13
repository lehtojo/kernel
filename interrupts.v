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

import kernel.scheduler

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
scheduler: Scheduler

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

	interrupt_handler = internal.get_interrupt_handler()
	entry_address = tables + INTERRUPT_ENTRIES_OFFSET

	debug.write('Interrupts: Interrupt handler address = ')
	debug.write_address(interrupt_handler)
	debug.write_line()

	loop (i = 0, i < INTERRUPT_COUNT, i++) {
		if i < 0x20 {
			set_interrupt(i, 0, entry_address)
		} else {
			set_trap(i, 0, entry_address)
		}

		entry_address = write_interrupt_entry(entry_address, interrupt_handler, i)
	}

	debug.write('Interrupts: IDTR = ')
	debug.write_address(tables + IDTR_OFFSET)
	debug.write_line()
	internal.interrupts_set_idtr(tables + IDTR_OFFSET)
}

export enable() {
	debug.write_line('Interrupts: Enabling interrupts')
	internal.interrupts_enable()
}

export disable() {
	debug.write_line('Interrupts: Disabling interrupts')
	internal.interrupts_disable()
}

# Summary:
# Writes an interrupt entry to the specified address that pushes the interrupt number to stack and jumps to the handler.
# Returns the address after writing the entry.
export write_interrupt_entry(address: link, to: link, interrupt: i32) {
	if interrupt < 0x20 {
		address[0] = 0x68 # push qword interrupt
		(address + 1).(i32*)[] = interrupt
		address += strideof(i32) + 1

		# Jump to the interrupt handler
		from = address + strideof(i32) + 1
		offset = to - from

		address[0] = 0xe9 # jmp to
		(address + 1).(i32*)[] = offset
		address += strideof(i32) + 1

		return address + 6 # Align to 16 bytes
	}

	# Align the stack to 16 bytes
	address[0] = 0x68 # push qword interrupt
	(address + 1).(i32*)[] = interrupt
	address += strideof(i32) + 1

	# Push the interrupt number so that the handler knows which interrupt is being called
	address[0] = 0x68 # push dword interrupt
	(address + 1).(i32*)[] = interrupt
	address += strideof(i32) + 1

	# Jump to the interrupt handler
	from = address + strideof(i32) + 1
	offset = to - from

	address[0] = 0xe9 # jmp to
	(address + 1).(i32*)[] = offset
	address += strideof(i32) + 1

	return address + 1 # Align to 16 bytes
}

export set_interrupt(index: u32, privilege: u8, handler: link) {
	# TODO: Add more checks
	privilege &= 3 # Take only the first two bits

	descriptor: InterruptDescriptor
	descriptor.offset_1 = (handler as u64)
	descriptor.selector = KERNEL_CODE_SELECTOR
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
	descriptor.selector = KERNEL_CODE_SELECTOR
	descriptor.interrupt_stack_table_offset = 1
	descriptor.type_attributes = PRESENT_BIT | (privilege <| 5) | GATE_TYPE_TRAP
	descriptor.offset_2 = ((handler as u64) |> 16)
	descriptor.offset_3 = ((handler as u64) |> 32)
	descriptor.reserved = 0

	(tables + IDT_OFFSET).(InterruptDescriptor*)[index] = descriptor
}

export process_page_fault(frame: TrapFrame*) {
	address = read_cr2()
	process = scheduler.current

	# Load the code location where the page fault occurred
	rip = frame[].registers[].rip 
	is_user_space = (rip as i64) >= 0

	# If the current process determines the page fault was legal, then continue
	# Todo: Continue
	if is_user_space and process !== none and process.memory !== none and process.memory.process_page_fault(address, false) return

	debug.write('Attempted to access address ')
	debug.write_address(address)
	debug.write(' at ')
	debug.write_address(rip)
	debug.write_line()
	panic('Page fault')
}

export process(frame: TrapFrame*): u64 {
	code = frame[].registers[].interrupt
	result = 0 as u64

	# Save all the registers so that they can be modified
	process = scheduler.current
	if process !== none { process.save(frame) }

	if code == 0x21 {
		keyboard.process()
	} else code == 0x24 {
		scheduler.tick(frame)
	} else code == 0x0e {
		process_page_fault(frame)
	} else code == 0x0d {
		debug.write('General protection fault at ')
		debug.write_address(frame[].registers[].rip)
		debug.write(' for address ')
		debug.write_address(read_cr2())
		debug.write_line()
		panic('General protection fault')
	} else code == 0x80 {
		result = system_calls.process(frame)
	} else {
		default_handler()
	}

	# Ensure interrupt flag is set after ending this interrupt
	frame[].registers[].rflags |= RFLAGS_INTERRUPT_FLAG

	# Report that we have processed the interrupt
	interrupts.end()

	# If the current process no longer runs, let the scheduler decide the next action
	process = scheduler.current
	if not process.is_running { scheduler.tick(frame) }

	return result
}

export end() {
	# Send the end-of-interrupt signal
	# 8259 PIC: ports.write_u8(0x20, 0x20)
	(apic.local_apic_registers + 0xB0)[] = 0
}

export default_handler() {}