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
		debug.write(' (rip=')
		debug.write_address(next.registers[].rip)
		debug.write_line(')')

		frame[].registers[] = next.registers[]

		current = next
	}

	enter(frame: TrapFrame*, next: Process) {
		debug.write('Scheduler: Entering to process ')
		debug.write_line(next.id)

		if current !== next switch(frame, next)
	}

	pick_and_enter(frame: TrapFrame*) {
		# Choose the next process to execute
		next = pick()
		if next === none return

		# Switch to the next process
		enter(frame, next)
	}

	tick(frame: TrapFrame*) {
		registers = frame[].registers
		#require(registers[].cs == KERNEL_CODE_SELECTOR and registers[].userspace_ss == KERNEL_DATA_SELECTOR, 'Illegal segment-register')
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

		pick_and_enter(frame)
	}

	exit(frame: TrapFrame*, process: Process) {
		# Remove the specified process from the process list
		loop (i = 0, i < processes.size, i++) {
			if processes[i] != process continue
			processes.remove_at(i)
			stop
		}

		process.dispose()
		KernelHeap.deallocate(process as link)

		pick_and_enter(frame)
	}
}

test(allocator: Allocator) {
	registers = KernelHeap.allocate<RegisterState>()
	process = Process(0, registers) using KernelHeap

	debug.write('Scheduler (test 1): Kernel stack address ') debug.write_address(registers_rsp()) debug.write_line()

	# TODO: Create a test process
	# Instructions:
	# mov r8, 7
	# mov rcx, 42
	# mov rax, 33
	# L0:
	# syscall
	# inc r8
	# jmp L0

	start = KernelHeap.allocate(0x100)
	stack = ((start + 0x100) & (-16))

	debug.write('Scheduler (test 1): Process code ') debug.write_address(start) debug.write_line()
	debug.write('Scheduler (test 1): Process stack ') debug.write_address(stack) debug.write_line()

	# mov r8, 7
	position = 0
	start[position++] = 0x49
	start[position++] = 0xc7
	start[position++] = 0xc0
	start[position++] = 0x07
	start[position++] = 0x00
	start[position++] = 0x00
	start[position++] = 0x00

	# mov rcx, 42
	start[position++] = 0x48
	start[position++] = 0xc7
	start[position++] = 0xc1
	start[position++] = 0x2a
	start[position++] = 0x00
	start[position++] = 0x00
	start[position++] = 0x00

	# mov rax, 33
	start[position++] = 0x48
	start[position++] = 0xc7
	start[position++] = 0xc0
	start[position++] = 0x21
	start[position++] = 0x00
	start[position++] = 0x00
	start[position++] = 0x00

	# syscall
	start[position++] = 0x0f
	start[position++] = 0x05

	# inc r8
	start[position++] = 0x49
	start[position++] = 0xff
	start[position++] = 0xc0

	# jmp L0
	start[position++] = 0xeb
	start[position++] = 0xf9

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