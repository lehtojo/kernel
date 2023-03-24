namespace kernel.system_calls

import kernel.scheduler

import 'C' get_system_call_handler(): link

constant ENOENT = -2
constant EBADF = -9
constant ENOMEM = -12
constant EFAULT = -14
constant EINVAL = -22
constant ESPIPE = -29
constant ENOTDIR = 20
constant EOVERFLOW = -75

constant DT_UNKNOWN = 0
constant DT_FIFO = 1
constant DT_CHR = 2
constant DT_DIR = 4
constant DT_BLK = 6
constant DT_REG = 8
constant DT_LNK = 10
constant DT_SOCK = 12

constant AT_FDCWD = 4294967196

constant MSR_EFER = 0xc0000080
constant MSR_STAR = 0xc0000081
constant MSR_LSTAR = 0xc0000082
constant MSR_SFMASK = 0xc0000084

# Summary: Returns the process that invoked the current system call
export get_process(): Process {
	process = interrupts.scheduler.current
	require(process !== none, 'System call required the current process, but the process was missing')
	return process
}

export load_string(allocator, string: link, limit: u32): Optional<String> {
	# Todo:
	# - Verify the address is mapped before loading bytes from it
	# - Verify passed pointers are accessible to this process
	length = 0
	loop (length < limit and string[length] != 0, length++) {}

	# If we reached the limit length, return none
	if length == limit return Optionals.empty<String>()

	# Allocate a new buffer for copying the characters
	data = allocator.allocate(length)
	if data === none return Optionals.empty<String>()

	# Copy the string from userspace
	memory.copy(data, string, length)

	return Optionals.new<String>(String.new(data, length))
}

# Summary: Returns whether the specified memory region is mapped and usable by the specified process
export is_valid_region(process: Process, start: link, size: u64): bool {
	return true
}

# Summary: Returns whether the specified system call code is an error
export is_error_code(code: u64) {
	return (code as i64) < 0
}

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

	if system_call_number == 0x00 {
		result = system_read(registers[].rdi as u32, registers[].rsi as link, registers[].rdx)
	} else system_call_number == 0x01 {
		result = system_write(registers[].rdi as u32, registers[].rsi as link, registers[].rdx)
	} else system_call_number == 0x02 {
		result = system_open(registers[].rdi as link, registers[].rsi as i32, registers[].rdx as u32)
	} else system_call_number == 0x03 {
		result = system_close(registers[].rdi as u32)
	} else system_call_number == 0x08 {
		result = system_seek(registers[].rdi as u32, registers[].rsi as i64, registers[].rdx as i32)
	} else system_call_number == 0x09 {
		result = system_memory_map(
			registers[].rdi as link, registers[].rsi, registers[].rdx as u32,
			registers[].r10 as u32, registers[].r8 as u32, registers[].r9
		)
	} else system_call_number == 0x0b {
		result = system_munmap(registers[].rdi as link, registers[].rsi)
	} else system_call_number == 0x11 {
		result = system_pread64(registers[].rdi as u32, registers[].rsi as link, registers[].rdx as u64, registers[].r10 as u64)
	} else system_call_number == 0x12 {
		result = system_pwrite64(registers[].rdi as u32, registers[].rsi as link, registers[].rdx as u64, registers[].r10 as u64)
	} else system_call_number == 0x0c {
		result = system_brk(registers[].rdi as u64)
	} else system_call_number == 0x14 {
		result = system_writev(registers[].rdi as u32, registers[].rsi as link, registers[].rdx as u64)
	} else system_call_number == 0x3b {
		result = system_execve(registers[].rdi as link, registers[].rsi as link, registers[].rdx as link)
	} else system_call_number == 0x3c {
		system_exit(frame, registers[].rdi as i32)
	} else system_call_number == 0xd9 {
		result = system_getdents64(registers[].rdi as u32, registers[].rsi as link, registers[].rdx as u64)
	} else system_call_number == 0xe7 {
		# System call: exit_group
	} else system_call_number == 0x9e {
		# System call: arch_prctl
	} else system_call_number == 0x101 {
		result = system_openat(registers[].rdi as i32, registers[].rsi as link, registers[].rdx as u32, registers[].r10 as u64)
	} else {
		# Todo: Handle this error
		debug.write('System calls: Unsupported system call ')
		debug.write_address(system_call_number)
		debug.write(': rip=')
		debug.write_address(frame[].registers[].rip)
		debug.write(', r8=')
		debug.write_address(frame[].registers[].r8)
		debug.write(', rcx=')
		debug.write_address(frame[].registers[].rcx)
		debug.write_line()
		panic('Unsupported system call')
	}

	return result
}