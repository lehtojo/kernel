namespace kernel.scheduler

import kernel.elf.loader

constant RFLAGS_INTERRUPT_FLAG = 1 <| 9

Process {
	constant NORMAL_PRIORITY = 50

	# Summary: Creates a process from the specified executable file
	shared from_executable(allocator: Allocator, file: Array<u8>): Process {
		debug.write_line('Process: Creating a process from executable...')

		allocations = List<MemoryMapping>(allocator)

		load_information = LoadInformation()
		load_information.allocations = allocations

		debug.write_line('Process: Loading executable into memory...')

		# Try loading the executable into memory
		if not load_executable(file, load_information) {
			allocations.clear()
			return none as Process
		}

		debug.write_line('Process: Creating process paging tables...')

		# Create paging tables for the process so that it can access memory correctly
		memory: ProcessMemory = ProcessMemory(allocator) using allocator
		paging_table = memory.paging_table

		# Todo: Regions are not reserved in the process memory
		# Todo: Add available regions to process memory before starting

		loop (i = 0, i < allocations.size, i++) {
			allocation = allocations[i]
			paging_table.map_region(allocator, allocation)

			# Register the allocation into the process memory.
			# When the process is destroyed, the allocation list is used to deallocate the memory.
			memory.allocations.add(allocation)
		}

		# The local allocation list is no longer needed
		allocations.clear()

		debug.write('Process: Setting process to entry point ')
		debug.write_address(load_information.entry_point)
		debug.write_line()

		register_state = allocator.allocate<RegisterState>()
		register_state[].rip = load_information.entry_point

		# Allocate and map stack for the process
		# Todo: Implement proper stack support, which means lazy allocation using page faults
		program_initial_stack_size = 512 * KiB
		program_stack_physical_address = PhysicalMemoryManager.instance.allocate_physical_region(program_initial_stack_size) as u64
		program_stack_virtual_address = 0x10000000
		program_stack_mapping = MemoryMapping.new(program_stack_virtual_address - program_initial_stack_size, program_stack_physical_address, program_initial_stack_size)
		memory.paging_table.map_region(allocator, program_stack_mapping)

		# Register the stack to the process
		register_state[].userspace_rsp = program_stack_virtual_address

		return Process(register_state, memory) using allocator
	}

	id: u64
	priority: u16 = NORMAL_PRIORITY
	registers: RegisterState*
	memory: ProcessMemory

	init(registers: RegisterState*, memory: ProcessMemory) {
		this.id = 0
		this.registers = registers
		this.memory = memory

		registers[].cs = USER_CODE_SELECTOR | 3
		registers[].rflags = RFLAGS_INTERRUPT_FLAG
		registers[].userspace_ss = USER_DATA_SELECTOR | 3
	}

	init(id: u64, registers: RegisterState*) {
		this.id = id
		this.registers = registers

		registers[].cs = USER_CODE_SELECTOR | 3
		registers[].rflags = RFLAGS_INTERRUPT_FLAG
		registers[].userspace_ss = USER_DATA_SELECTOR | 3
	}

	save(frame: TrapFrame*) {
		registers[] = frame[].registers[]
	}

	dispose() {
		# Dispose the register state
		if registers !== none KernelHeap.deallocate(registers)

		# Dispose the process memory
		if memory !== none {
			memory.dispose()
			KernelHeap.deallocate(registers)
		}
	}
}