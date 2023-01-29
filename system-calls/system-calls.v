namespace kernel.system_calls

import 'C' get_system_call_handler(): link

constant SYSTEM_CALL_ERROR_NO_MEMORY = -1

constant MSR_EFER = 0xc0000080
constant MSR_STAR = 0xc0000081
constant MSR_LSTAR = 0xc0000082
constant MSR_SFMASK = 0xc0000084

export initialize() {
	debug.write_line('System calls: Initializing system calls')

	# Enable the system call extension
	write_msr(MSR_EFER, read_msr(MSR_EFER) | 1)

	# Write code and stack selectors to the STAR MSR.
	# Bits 32..48: After syscall instruction CS=$value and SS=$value+0x8
	# Bits 48..64: After sysret instruction CS=$value+? and SS=$value+?
	star = read_msr(MSR_STAR) & 0x00000000ffffffff
	star |= KERNEL_CODE_SELECTOR <| 32
	star |= (((USER_CODE_SELECTOR - 0x10) | 3) <| 48)
	write_msr(MSR_STAR, star)

	# Write the address of system call handler, so that system calls can be invoked
	system_call_handler = get_system_call_handler() as u64
	debug.write('System calls: Register system call handler ')
	debug.write_address(system_call_handler)
	debug.write_line()

	write_msr(MSR_LSTAR, system_call_handler)

	# MSR_SFMASK:
	# - Controls the bits of rflags that are cleared before entering the system call handler.
	# - Bits are set up so that interrupts are disabled before entering the system call handler. 
	write_msr(MSR_SFMASK, 0x257fd5)

	# Disable instructions that can interact with the GS and FS registers.
	# GS register is used to save the user stack and switch to kernel stack during system calls.
	write_cr4(read_cr4() & (!0x10000))
}

export process(frame: TrapFrame*): u64 {
	registers = frame[].registers
	system_call_number = registers[].rax
	result = 0 as u64

	if system_call_number == 1 {
		system_write(registers[].rdi as u32, registers[].rsi as link, registers[].rdx)
	} else system_call_number == 9 {
		result = system_memory_map(
			registers[].rdi as link, registers[].rsi, registers[].rdx as u32,
			registers[].r10 as u32, registers[].r8 as u32, registers[].r9
		)
	} else system_call_number == 0x80 {
		system_exit(frame, registers[].rdi as i32)
	} else {
		# Todo: Handle this error
		debug.write('System calls: Unsupported system call ')
		debug.write('rip=')
		debug.write_address(frame[].registers[].rip)
		debug.write(', r8=')
		debug.write_address(frame[].registers[].r8)
		debug.write(', rcx=')
		debug.write_address(frame[].registers[].rcx)
		debug.write_line()
	}

	return result
}