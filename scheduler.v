namespace kernel.scheduler

import 'C' registers_rsp(): u64

Scheduler {
	allocator: Allocator
	current: Process
	processes: List<Process>

	init(allocator: Allocator) {
		this.allocator = allocator
		this.processes = List<Process>(allocator, 256, false) using allocator
	}

	add(process: Process) {
		processes.add(process)
	}

	pick(): Process {
		return processes[0]
	}

	switch(frame: TrapFrame*, next: Process) {
		debug.write('Scheduler: Switching to process ')
		debug.write(next.id)
		debug.write_line()

		frame[].registers[] = next.registers[]

		current = next
	}

	enter(frame: TrapFrame*, next: Process) {
		debug.write('Scheduler: Entering to process ')
		debug.write_line(next.id)

		if current !== next switch(frame, next)
	}

	tick(frame: TrapFrame*) {
		registers = frame[].registers
		require(registers[].cs == CODE_SEGMENT and registers[].userspace_ss == DATA_SEGMENT, 'Illegal segment-register')
		require((registers[].rflags & RFLAGS_INTERRUPT_FLAG) != 0, 'Illegal flags-register')
		# TODO: Verify IOPL and RSP

		debug.write('Scheduler: Kernel stack = ')
		debug.write_address(registers_rsp())
		debug.write_line()

		# Save the state of the current process
		if current !== none {
			current.save(frame)

			debug.write('Scheduler: User process: ')
			debug.write('rip=')
			debug.write_address(current.registers[].rip)
			debug.write(', r8=')
			debug.write_address(current.registers[].r8)
			debug.write(', rcx=')
			debug.write_address(current.registers[].rcx)
			debug.write_line()
		}

		# Choose the next process to execute
		next = pick()
		if next === none return

		# Switch to the next process
		enter(frame, next)
	}
}

test(allocator: Allocator) {
	registers = KernelHeap.allocate<RegisterState>()
	process = Process(0, registers) using KernelHeap

	debug.write('Scheduler (test 1): Kernel stack address ') debug.write_address(registers_rsp()) debug.write_line()

	# TODO: Create a test process
	# Instructions:
	# mov r8, 42
	# L0:
	# inc r8
	# jmp L0

	start = KernelHeap.allocate(0x100)
	stack = ((start + 0x100) & (-16))

	debug.write('Scheduler (test 1): Process code ') debug.write_address(start) debug.write_line()
	debug.write('Scheduler (test 1): Process stack ') debug.write_address(stack) debug.write_line()

	start[0] = 0x49
	start[1] = 0xc7
	start[2] = 0xc0
	start[3] = 0x07
	start[4] = 0x00
	start[5] = 0x00
	start[6] = 0x00

	start[7] = 0x48
	start[8] = 0xc7
	start[9] = 0xc1
	start[10] = 0x2a
	start[11] = 0x00
	start[12] = 0x00
	start[13] = 0x00

	start[14] = 0x49
	start[15] = 0xff
	start[16] = 0xc0
	start[17] = 0xeb
	start[18] = 0xfb

	process.registers[].rip = start
	process.registers[].userspace_rsp = stack

	interrupts.scheduler.add(process)
}

export test2(allocator: Allocator, memory_information: SystemMemoryInformation) {
	symbols = memory_information.symbols
	application_start = none as link
	application_end = none as link

	debug.write_line('Scheduler: Searching for the test application...')

	loop (i = 0, i < symbols.size, i++) {
		symbol = symbols[i]

		if symbol.name == 'application_start' {
			application_start = symbol.address
			debug.write('Scheduler (test 2): Found start of application data at ')
			debug.write_address(application_start)
			debug.write_line()
		} else symbol.name == 'application_end' {
			application_end = symbol.address
			debug.write('Scheduler (test 2): Found end of application data at ')
			debug.write_address(application_end)
			debug.write_line()
		}
	}

	if application_start === none or application_end === none return

	application_size = (application_end - application_start) as u64
	application_data = Array<u8>(application_start, application_size)

	process = kernel.scheduler.Process.from_executable(allocator, application_data)

	#interrupts.scheduler.add(process)
}