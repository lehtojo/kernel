namespace kernel.scheduler

Scheduler {
	allocator: Allocator
	current: Process
	processes: List<Process>
	next_process_id: u32

	init(allocator: Allocator) {
		this.allocator = allocator
		this.processes = List<Process>(allocator, 256, false) using allocator
		this.next_process_id = 1
	}

	add(process: Process) {
		process.id = next_process_id++
		processes.add(process)
	}

	# Summary: Attempts to find a process by the specified pid
	find(pid: u32): Optional<Process> {
		loop (i = 0, i < processes.size, i++) {
			process = processes[i]
			if process.id == pid return Optionals.new<Process>(process)
		}

		return Optionals.empty<Process>()
	}

	pick(): Process {
		result = processes[0]
		processes.remove_at(0)
		processes.add(result)

		return result
	}

	switch(frame: TrapFrame*, next: Process) {
		debug.write('Scheduler: Switching to process ')
		debug.write(next.id)
		debug.write(' (rip=')
		debug.write_address(next.registers[].rip)
		debug.write_line(')')

		frame[].registers[] = next.registers[]

		current = next

		# Map the process to memory
		if next.memory !== none next.memory.paging_table.use()
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
		debug.write('Scheduler: Exiting process ') debug.write_line(process.id)

		# Remove the specified process from the process list
		loop (i = 0, i < processes.size, i++) {
			if processes[i] != process continue
			processes.remove_at(i)
			stop
		}

		debug.write('Scheduler: Destructing process ') debug.write_line(process.id)
		process.destruct(HeapAllocator.instance)

		debug.write_line('Scheduler: Picking next process after exiting process')
		pick_and_enter(frame)
	}
}

test(allocator: Allocator) {
	registers = KernelHeap.allocate<RegisterState>()

	debug.write('Scheduler (test 1): Kernel stack address ') debug.write_address(registers_rsp()) debug.write_line()

	# Instructions:
	# mov r8, 7
	# mov rcx, 42
	# mov rax, 33
	# L0:
	# syscall
	# inc r8
	# jmp L0

	memory = ProcessMemory(HeapAllocator.instance) using KernelHeap

	text_section_virtual_address = KernelHeap.allocate(0x1000)
	stack_virtual_address = KernelHeap.allocate(0x1000)
	text_section_physical_address = mapper.to_physical_address(text_section_virtual_address)
	stack_physical_address = mapper.to_physical_address(stack_virtual_address)

	debug.write('Scheduler (test 1): Process code ') debug.write_address(text_section_physical_address) debug.write_line()
	debug.write('Scheduler (test 1): Process stack ') debug.write_address(stack_physical_address) debug.write_line()

	program_text_section_virtual_address = 0x400000 as link
	program_stack_virtual_address = 0x690000 as link

	memory.paging_table.map_page(HeapAllocator.instance, program_text_section_virtual_address, text_section_physical_address)
	memory.paging_table.map_page(HeapAllocator.instance, program_stack_virtual_address, stack_physical_address)

	# mov r8, 7
	position = 0
	text_section_virtual_address[position++] = 0x49
	text_section_virtual_address[position++] = 0xc7
	text_section_virtual_address[position++] = 0xc0
	text_section_virtual_address[position++] = 0x07
	text_section_virtual_address[position++] = 0x00
	text_section_virtual_address[position++] = 0x00
	text_section_virtual_address[position++] = 0x00

	# mov rcx, 42
	text_section_virtual_address[position++] = 0x48
	text_section_virtual_address[position++] = 0xc7
	text_section_virtual_address[position++] = 0xc1
	text_section_virtual_address[position++] = 0x2a
	text_section_virtual_address[position++] = 0x00
	text_section_virtual_address[position++] = 0x00
	text_section_virtual_address[position++] = 0x00

	# mov rax, 33
	text_section_virtual_address[position++] = 0x48
	text_section_virtual_address[position++] = 0xc7
	text_section_virtual_address[position++] = 0xc0
	text_section_virtual_address[position++] = 0x21
	text_section_virtual_address[position++] = 0x00
	text_section_virtual_address[position++] = 0x00
	text_section_virtual_address[position++] = 0x00

	# syscall
	# text_section_virtual_address[position++] = 0x0f
	# text_section_virtual_address[position++] = 0x05

	# nop nop
	text_section_virtual_address[position++] = 0x90
	text_section_virtual_address[position++] = 0x90

	# inc r8
	text_section_virtual_address[position++] = 0x49
	text_section_virtual_address[position++] = 0xff
	text_section_virtual_address[position++] = 0xc0

	# jmp L0
	text_section_virtual_address[position++] = 0xeb
	text_section_virtual_address[position++] = 0xf9

	file_descriptors = ProcessFileDescriptors(allocator, 256) using KernelHeap

	process = Process(registers, memory, file_descriptors) using KernelHeap
	process.registers[].rip = program_text_section_virtual_address
	process.registers[].userspace_rsp = program_stack_virtual_address + 0x100

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

	mapped_application_start = mapper.map_kernel_region(application_start, application_size)
	application_data = Array<u8>(mapped_application_start, application_size)

	process = Process.from_executable(allocator, application_data)
	if process === none panic('Scheduler (test 2): Failed to create the process')

	debug.write_line('Scheduler (test 2): Process created')

	interrupts.scheduler.add(process)
}