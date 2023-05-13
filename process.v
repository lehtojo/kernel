namespace kernel.scheduler

import kernel.file_systems
import kernel.elf.loader
import kernel.devices.console

constant RFLAGS_INTERRUPT_FLAG = 1 <| 9

Process {
	constant NORMAL_PRIORITY = 50

	private shared attach_standard_files(allocator: Allocator, file_descriptors: ProcessFileDescriptors) {
		standard_input_descriptor = file_descriptors.allocate().or_panic('Failed to create standard input descriptor for a process')
		require(standard_input_descriptor == 0, 'Created invalid standard input descriptor')
		standard_input_file = ConsoleDevice(allocator, 0, 0) using allocator
		file_descriptors.attach(standard_input_descriptor, standard_input_file.create_file_description(allocator, none as Custody))
	
		standard_output_descriptor = file_descriptors.allocate().or_panic('Failed to create standard output descriptor for a process')
		require(standard_output_descriptor == 1, 'Created invalid standard output descriptor')
		standard_output_file = ConsoleDevice(allocator, 0, 0) using allocator
		file_descriptors.attach(standard_output_descriptor, standard_input_file.create_file_description(allocator, none as Custody))
		
		standard_error_descriptor = file_descriptors.allocate().or_panic('Failed to create standard error descriptor for a process')
		require(standard_error_descriptor == 2, 'Created invalid standard error descriptor')
		standard_error_file = ConsoleDevice(allocator, 0, 0) using allocator
		file_descriptors.attach(standard_error_descriptor, standard_input_file.create_file_description(allocator, none as Custody))
	}

	# Summary: Adds the allocations in the specified load information to the specified process memory
	private shared add_allocations_to_process_memory(memory: ProcessMemory, load_information: LoadInformation): _ {
		allocations = load_information.allocations

		loop (i = 0, i < allocations.size, i++) {
			allocation = allocations[i]

			# Reserve the allocation from the process memory
			# When the process is destroyed, the allocation list is used to deallocate the memory.
			memory.add_allocation(allocation.type, ProcessMemoryRegion.new(allocation))

			# Set the program break after all loaded segments
			memory.break = math.max(memory.break, allocation.end as u64)
		}
	}

	# Summary: Configures the specified register state based on the specified load information
	private shared configure_process_before_startup(allocator: Allocator, register_state: RegisterState*, memory: ProcessMemory, load_information: LoadInformation): _ {
		debug.write_line('Process: Configuring process before starting...')

		# Set the process to start at the entry point
		debug.write('Process: Setting process to entry point ')
		debug.write_address(load_information.entry_point)
		debug.write_line()
	
		register_state[].rip = load_information.entry_point

		# Allocate and map stack for the process
		# Todo: Implement proper stack support, which means lazy allocation using page faults
		program_initial_stack_size = 512 * KiB
		program_stack_physical_address_bottom = PhysicalMemoryManager.instance.allocate_physical_region(program_initial_stack_size) as u64
		program_stack_physical_address_top = program_stack_physical_address_bottom + program_initial_stack_size
		program_stack_virtual_address_top = 0x10000000
		program_stack_virtual_address_bottom = program_stack_virtual_address_top - program_initial_stack_size
		program_stack_mapping = MemoryMapping.new(program_stack_virtual_address_bottom, program_stack_physical_address_bottom, program_initial_stack_size)

		# Add environment variables and arguments for the application
		arguments = List<String>(allocator)
		arguments.add(String.new('/bin/ld')) # Todo: Add executable path
		# arguments.add(String.new('--help'))
		arguments.add(String.new('/bin/sh'))
		# arguments.add(String.new('/bin/startup'))

		environment_variables = List<String>(allocator)
		environment_variables.add(String.new('PATH=/bin/:/lib/')) # Todo: Load proper environment variables
		# environment_variables.add(String.new('LD_DEBUG=all'))

		startup_data_size = load_stack_startup_data(program_stack_physical_address_top, program_stack_virtual_address_top, arguments, environment_variables)
		program_stack_pointer = program_stack_virtual_address_top - startup_data_size

		# Map the stack memory for the application
		memory.paging_table.map_region(allocator, program_stack_mapping)

		# Register the stack to the process
		register_state[].userspace_rsp = program_stack_pointer
	}

	# Summary: Creates a process from the specified executable file
	shared from_executable(allocator: Allocator, file: Array<u8>): Process {
		debug.write_line('Process: Creating a process from executable...')

		allocations = List<Segment>(allocator)

		load_information = LoadInformation()
		load_information.allocations = allocations

		debug.write_line('Process: Creating process paging tables...')

		# Create paging tables for the process so that it can access memory correctly
		memory: ProcessMemory = ProcessMemory(allocator) using allocator
		paging_table = memory.paging_table

		debug.write_line('Process: Loading executable into memory...')

		# Try loading the executable into memory
		if not load_executable(allocator, paging_table, file, load_information) {
			allocations.clear()
			return none as Process
		}

		# Add the allocations from the load information to the process memory
		add_allocations_to_process_memory(memory, load_information)

		# The local allocation list is no longer needed
		allocations.clear()

		# Allocate register state for the process so that we can configure the registers before starting
		register_state = allocator.allocate<RegisterState>()
		configure_process_before_startup(allocator, register_state, memory, load_information)

		# Attach the standard files for the new process
		file_descriptors: ProcessFileDescriptors = ProcessFileDescriptors(allocator, 256) using allocator
		attach_standard_files(allocator, file_descriptors)

		process = Process(register_state, memory, file_descriptors) using allocator
		process.working_directory = String.new('/bin/')

		return process
	}

	id: u64
	priority: u16 = NORMAL_PRIORITY
	registers: RegisterState*
	memory: ProcessMemory
	file_descriptors: ProcessFileDescriptors
	working_directory: String
	credentials: Credentials
	blocker: Blocker
	state: u32
	parent: Process

	is_running => state == THREAD_STATE_RUNNING
	is_blocked => state == THREAD_STATE_BLOCKED
	is_sleeping => state == THREAD_STATE_SLEEPING
	is_terminated => state == THREAD_STATE_TERMINATED

	init(registers: RegisterState*, memory: ProcessMemory, file_descriptors: ProcessFileDescriptors) {
		this.id = 0
		this.registers = registers
		this.memory = memory
		this.file_descriptors = file_descriptors
		this.working_directory = String.empty

		registers[].cs = USER_CODE_SELECTOR | 3
		registers[].rflags = RFLAGS_INTERRUPT_FLAG
		registers[].userspace_ss = USER_DATA_SELECTOR | 3
	}

	init(id: u64, registers: RegisterState*) {
		this.id = id
		this.registers = registers
		this.working_directory = String.empty

		registers[].cs = USER_CODE_SELECTOR | 3
		registers[].rflags = RFLAGS_INTERRUPT_FLAG
		registers[].userspace_ss = USER_DATA_SELECTOR | 3
	}

	save(frame: TrapFrame*): _ {
		registers[] = frame[].registers[]
	}

	# Summary: Loads the specified program into this process
	load(allocator: Allocator, file: Array<u8>): i32 {
		debug.write_line('Process: Loading program into process...')

		allocations = List<Segment>(allocator)

		load_information = LoadInformation()
		load_information.allocations = allocations

		# Try loading the executable into memory
		if not load_executable(allocator, memory.paging_table, file, load_information) {
			allocations.clear()
			return ENOEXEC
		}

		# Add the allocations from the load information to the process memory
		add_allocations_to_process_memory(memory, load_information)

		# The local allocation list is no longer needed
		allocations.clear()

		# Todo: Reset the registers and other stuff

		# Allocate register state for the process so that we can configure the registers before starting
		configure_process_before_startup(allocator, registers, memory, load_information)
		return 0
	}

	# Summary: Blocks the process
	block(blocker: Blocker): _ {
		debug.write_line('Process: Blocking...')

		require(this.blocker === none and state == THREAD_STATE_RUNNING, 'Invalid thread state')
		this.blocker = blocker
		this.blocker.process = this

		interrupts.scheduler.change_process_state(this, THREAD_STATE_BLOCKED)
	}

	# Summary: Unblocks the process
	unblock(): _ {
		debug.write_line('Process: Unblocking...')

		require(this.blocker !== none and state == THREAD_STATE_BLOCKED, 'Invalid thread state')
		this.blocker = none as Blocker
		this.blocker.process = none as Process

		interrupts.scheduler.change_process_state(this, THREAD_STATE_RUNNING)
	}

	destruct(allocator: Allocator): _ {
		# Dispose the register state
		if registers !== none KernelHeap.deallocate(registers)

		# Destruct the process memory
		if memory !== none {
			memory.destruct()
		}

		allocator.deallocate(this as link)
	}
}