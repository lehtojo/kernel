namespace kernel.scheduler

import kernel.file_systems
import kernel.elf.loader

constant RFLAGS_INTERRUPT_FLAG = 1 <| 9

Process {
	constant NORMAL_PRIORITY = 50

	private shared attach_standard_files(allocator: Allocator, file_descriptors: ProcessFileDescriptors) {
		# Todo: Do not use an inode file here, create a memory backed file (inodes are used for file systems)
		standard_input_descriptor = file_descriptors.allocate().or_panic('Failed to create standard input descriptor for a process')
		require(standard_input_descriptor == 0, 'Created invalid standard input descriptor')
		standard_input_inode = MemoryInode(allocator, none as FileSystem, -1, String.new('STANDARD_INPUT')) using allocator
		standard_input_file = InodeFile(standard_input_inode) using allocator
		file_descriptors.attach(standard_input_descriptor, OpenFileDescription.try_create(allocator, standard_input_file))
		
		# Todo: Do not use an inode file here, create a memory backed file (inodes are used for file systems)
		standard_output_descriptor = file_descriptors.allocate().or_panic('Failed to create standard output descriptor for a process')
		require(standard_output_descriptor == 1, 'Created invalid standard output descriptor')
		standard_output_inode = MemoryInode(allocator, none as FileSystem, -1, String.new('STANDARD_OUTPUT')) using allocator
		standard_output_file = InodeFile(standard_output_inode) using allocator
		file_descriptors.attach(standard_output_descriptor, OpenFileDescription.try_create(allocator, standard_output_file))
		
		# Todo: Do not use an inode file here, create a memory backed file (inodes are used for file systems)
		standard_error_descriptor = file_descriptors.allocate().or_panic('Failed to create standard error descriptor for a process')
		require(standard_error_descriptor == 2, 'Created invalid standard error descriptor')
		standard_error_inode = MemoryInode(allocator, none as FileSystem, -1, String.new('STANDARD_ERROR')) using allocator
		standard_error_file = InodeFile(standard_error_inode) using allocator
		file_descriptors.attach(standard_error_descriptor, OpenFileDescription.try_create(allocator, standard_error_file))
	}

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

		loop (i = 0, i < allocations.size, i++) {
			allocation = allocations[i]
			paging_table.map_region(allocator, allocation)

			# Reserve the allocated virtual region
			unaligned_size = (allocation.virtual_address_start + allocation.size) - allocation.unaligned_virtual_address_start

			require(memory.reserve_specific_region(
				allocation.unaligned_virtual_address_start,
				unaligned_size
			), 'Failed to reserve memory region before starting the process')

			# Register the allocation into the process memory.
			# When the process is destroyed, the allocation list is used to deallocate the memory.
			memory.add_allocation(Segment.new(
				allocation.unaligned_virtual_address_start as link,
				allocation.virtual_address_end as link
			))

			# Set the program break after all loaded segments
			memory.break = math.max(memory.break, allocation.virtual_address_end)
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
		program_stack_physical_address_bottom = PhysicalMemoryManager.instance.allocate_physical_region(program_initial_stack_size) as u64
		program_stack_physical_address_top = program_stack_physical_address_bottom + program_initial_stack_size
		program_stack_virtual_address_top = 0x10000000
		program_stack_virtual_address_bottom = program_stack_virtual_address_top - program_initial_stack_size
		program_stack_mapping = MemoryMapping.new(program_stack_virtual_address_bottom, program_stack_physical_address_bottom, program_initial_stack_size)

		# Add environment variables and arguments for the application
		arguments = List<String>(allocator)
		arguments.add(String.new('/bin/test2')) # Todo: Add executable path
		# arguments.add(String.new('--help'))
		# arguments.add(String.new('/bin/hello'))
		arguments.add(String.new('/bin/startup'))

		environment_variables = List<String>(allocator)
		environment_variables.add(String.new('PATH=/bin/')) # Todo: Load proper environment variables

		startup_data_size = load_stack_startup_data(program_stack_physical_address_top, program_stack_virtual_address_top, arguments, environment_variables)
		program_stack_pointer = program_stack_virtual_address_top - startup_data_size

		# Map the stack memory for the application
		memory.paging_table.map_region(allocator, program_stack_mapping)

		# Register the stack to the process
		register_state[].userspace_rsp = program_stack_pointer

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

	save(frame: TrapFrame*) {
		registers[] = frame[].registers[]
	}

	destruct(allocator: Allocator) {
		# Dispose the register state
		if registers !== none KernelHeap.deallocate(registers)

		# Destruct the process memory
		if memory !== none {
			memory.destruct()
		}

		allocator.deallocate(this as link)
	}
}