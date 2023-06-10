namespace kernel.system_calls

import kernel.scheduler

import 'C' get_system_call_handler(): link

constant F_OK = 0

constant F_DUPFD = 0

constant ENOENT = -2
constant ESRCH = -3
constant EIO = -5
constant ENXIO = -6
constant ENOEXEC = -8
constant EBADF = -9
constant ENOMEM = -12
constant EFAULT = -14
constant EINVAL = -22
constant ENOTTY = -25
constant ESPIPE = -29
constant ENOTDIR = -20
constant ERANGE = -34
constant EOVERFLOW = -75

constant DT_UNKNOWN = 0
constant DT_FIFO = 1
constant DT_CHR = 2
constant DT_DIR = 4
constant DT_BLK = 6
constant DT_REG = 8
constant DT_LNK = 10
constant DT_SOCK = 12

constant AT_EMPTY_PATH = 0x1000
constant AT_FDCWD = 4294967196

constant ARCH_SET_FS = 0x1002
constant ARCH_GET_FS = 0x1003

constant MSR_EFER = 0xc0000080
constant MSR_STAR = 0xc0000081
constant MSR_LSTAR = 0xc0000082
constant MSR_SFMASK = 0xc0000084

constant PATH_MAX = 256
constant MAX_ARGUMENTS = 256
constant MAX_ENVIRONMENT_VARIABLES = 256

# Summary: Returns the process that invoked the current system call
export get_process(): Process {
	process = interrupts.scheduler.current
	require(process !== none, 'System call required the current process, but the process was missing')
	return process
}

# Summary: Returns the number of elements before zero	while taking into account the specified limit
export count<T>(process: Process, start: T*, limit: u32): i64 {
	process_memory = process.memory
	count = 0

	loop {
		# If we have reached the limit, return -1
		if count == limit return -1

		# If the first byte of the element is not accessible, return -1
		if not process_memory.is_accessible(start) and 
			not process_memory.process_page_fault(start as u64, false) {
			return -1
		}

		# If the last byte of the element is not accessible, return -1
		end = start + strideof(T) - 1

		if not process_memory.is_accessible(end) and 
			not process_memory.process_page_fault(end as u64, false) {
			return -1
		}

		# If we have found the zero, stop
		if start[] == 0 stop

		start += strideof(T)
		count++
	}

	return count
}

export load_string(allocator, process: Process, string: link, limit: u32): Optional<String> {
	process_memory = process.memory
	length = 0

	loop {
		address = string + length

		# If we have reached the limit, return none string
		if length == limit return Optionals.empty<String>()

		# If the character is not accessible, return none string
		if not process_memory.is_accessible(address) and 
			not process_memory.process_page_fault(address as u64, false) {
			return Optionals.empty<String>()
		}

		# If we have found the end of the string, stop
		if address[] == 0 stop

		length++
	}

	# Allocate a new buffer for copying the characters
	data = allocator.allocate(length)
	if data === none return Optionals.empty<String>()

	# Copy the string from userspace
	memory.copy(data, string, length)

	return Optionals.new<String>(String.new(data, length))
}

export load_strings(allocator, process: Process, destination: List<String>, source: link*, size: u64): bool {
	loop (i = 0, i < size, i++) {
		if load_string(allocator, process, source[i], PATH_MAX) has not string return false
		destination.add(string)
	}

	return true
}

# Summary: Returns whether the specified memory region is mapped and usable by the specified process
export is_valid_region(process: Process, start: link, size: u64, write: bool): bool {
	start_page = memory.page_of(start)
	end_page = memory.round_to_page(start + size)

	loop (virtual_page = start_page, virtual_page < end_page, virtual_page += PAGE_SIZE) {
		# If the page is accessible or becomes accessible after page fault, there is no problem
		if process.memory.is_accessible(Segment.new(virtual_page, virtual_page + PAGE_SIZE)) or 
			process.memory.process_page_fault(virtual_page as u64, write) {
			continue
		}

		return false
	}
	
	return true		 
}

# Summary: Returns whether the specified system call code is an error
export is_error_code(code: u64) {
	return (code as i64) < 0
}

# Summary: Enables instructions that edit FS and GS segment registers
export enable_general_purpose_segment_instructions(): _ {
	write_cr4(read_cr4() | 0x10000)
}

# Summary: Disables instructions that edit FS and GS segment registers
export disable_general_purpose_segment_instructions(): _ {
	write_cr4(read_cr4() & (!0x10000))
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
	disable_general_purpose_segment_instructions()
}

export process(frame: TrapFrame*): u64 {
	process = get_process()

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
	} else system_call_number == 0x04 {
		result = system_stat(registers[].rdi as link, registers[].rsi as link)
	} else system_call_number == 0x05 {
		result = system_fstat(registers[].rdi as u32, registers[].rsi as link)
	} else system_call_number == 0x08 {
		result = system_seek(registers[].rdi as u32, registers[].rsi as i64, registers[].rdx as i32)
	} else system_call_number == 0x09 {
		result = system_memory_map(
			registers[].rdi as link, registers[].rsi, registers[].rdx as u32,
			registers[].r10 as u32, registers[].r8 as u32, registers[].r9
		)
	} else system_call_number == 0x0a {
		result = system_mprotect(registers[].rdi as u64, registers[].rsi as u64, registers[].rdx as u64)
	} else system_call_number == 0x0b {
		result = system_munmap(registers[].rdi as link, registers[].rsi)
	} else system_call_number == 0x0d {
		result = system_rt_sigaction(registers[].rdi as i32, registers[].rsi as link, registers[].rdx as link)
	} else system_call_number == 0x0e {
		result = system_rt_sigprocmask(registers[].rdi as i32, registers[].rsi as link, registers[].rdx as link, registers[].r10 as u64)
	} else system_call_number == 0x10 {
		result = system_ioctl(registers[].rdi as u32, registers[].rsi as u32, registers[].rdx as u64)
	} else system_call_number == 0x11 {
		result = system_pread64(registers[].rdi as u32, registers[].rsi as link, registers[].rdx as u64, registers[].r10 as u64)
	} else system_call_number == 0x12 {
		result = system_pwrite64(registers[].rdi as u32, registers[].rsi as link, registers[].rdx as u64, registers[].r10 as u64)
	} else system_call_number == 0x15 {
		result = system_access(registers[].rdi as link, registers[].rsi as u64)
	} else system_call_number == 0x0c {
		result = system_brk(registers[].rdi as u64)
	} else system_call_number == 0x14 {
		result = system_writev(registers[].rdi as u32, registers[].rsi as link, registers[].rdx as u64)
	} else system_call_number == 0x27 {
		result = system_getpid()
	} else system_call_number == 0x3a {
		result = system_vfork()
	} else system_call_number == 0x3b {
		result = system_execve(registers[].rdi as link, registers[].rsi as link, registers[].rdx as link)
	} else system_call_number == 0x3c {
		system_exit(frame, registers[].rdi as i32)
	} else system_call_number == 0x3f {
		system_uname(registers[].rdi as link)
	} else system_call_number == 0x48 {
		result = system_fcntl(registers[].rdi as u32, registers[].rsi as u32, registers[].rdx as u64)
	} else system_call_number == 0x4f {
		result = system_getcwd(registers[].rdi as link, registers[].rsi as u64)
	} else system_call_number == 0x66 {
		result = system_getuid()
	} else system_call_number == 0x68 {
		result = system_getgid()
	} else system_call_number == 0x6b {
		result = system_geteuid()
	} else system_call_number == 0x6c {
		result = system_getegid()
	} else system_call_number == 0x6d {
		result = system_setpgrp(registers[].rdi as u32, registers[].rsi as u32)
	} else system_call_number == 0x6e {
		result = system_getppid()
	} else system_call_number == 0x6f {
		result = system_getpgrp()
	} else system_call_number == 0xd9 {
		result = system_getdents64(registers[].rdi as u32, registers[].rsi as link, registers[].rdx as u64)
	} else system_call_number == 0xda {
		result = system_set_tid_address(registers[].rdi as u64)
	} else system_call_number == 0xe7 {
		# System call: exit_group
	} else system_call_number == 0x9e {
		result = system_arch_prctl(registers[].rdi as u32, registers[].rsi as u64)
	} else system_call_number == 0x101 {
		result = system_openat(registers[].rdi as i32, registers[].rsi as link, registers[].rdx as u32, registers[].r10 as u64)
	} else system_call_number == 0x111 {
		result = system_set_robust_list(registers[].rdi as link, registers[].rsi as u64)
	} else system_call_number == 0x106 {
		result = system_fstatat(registers[].rdi as u32, registers[].rsi as link, registers[].rdx as link, registers[].r10 as u32)
	} else system_call_number == 0x12e {
		result = system_prlimit(registers[].rdi as u64, registers[].rsi as u64, registers[].rdx as link, registers[].r10 as link)
	} else system_call_number == 0x13e {
		result = system_getrandom(registers[].rdi as link, registers[].rsi as u64, registers[].rdx as u32)
	} else system_call_number == 0x14e {
		result = system_faccessat(registers[].rdi as u64, registers[].rdi as link, registers[].rdx as u64)
	} else {
		# Todo: Handle this error
		debug.write('System calls: Unsupported system call ')
		debug.write_address(system_call_number)
		debug.write_line()
		panic('Unsupported system call')
	}

	# Load updated registers
	process = get_process()
	process.registers[].rax = result
	frame[].registers[] = process.registers[]

	return result
}