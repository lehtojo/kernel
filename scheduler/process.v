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

	# Summary: Allocates kernel stack for the specified process memory
	private shared allocate_kernel_stack(memory: ProcessMemory): _ {
		debug.write_line('Process: Allocating kernel stack memory for the process')
		kernel_stack_pointer = KernelHeap.allocate(512 * KiB)

		# Zero out the kernel stack memory
		global.memory.zero(kernel_stack_pointer, 512 * KiB)

		# Store the kernel stack pointer for use
		memory.kernel_stack_pointer = (kernel_stack_pointer + 512 * KiB) as u64
	}

	# Summary: Configures the specified register state based on the specified load information
	private shared configure_process_before_startup(
		allocator: Allocator,
		register_state: RegisterState*,
		memory: ProcessMemory,
		load_information: LoadInformation,
		arguments: List<String>,
		environment_variables: List<String>
	): _ {
		debug.write_line('Process: Configuring process before starting...')

		# Set the process to start at the entry point
		debug.write('Process: Setting process to entry point ')
		debug.write_address(load_information.entry_point)
		debug.write_line()
	
		register_state[].rip = load_information.entry_point

		# Allocate and map stack for the process
		debug.write_line('Process: Allocating process stack memory')
		# Todo: Implement proper stack support, which means lazy allocation using page faults
		program_initial_stack_size = 512 * KiB
		program_stack_physical_address_bottom = PhysicalMemoryManager.instance.allocate_physical_region(program_initial_stack_size) as u64
		program_stack_physical_address_top = program_stack_physical_address_bottom + program_initial_stack_size
		program_stack_virtual_address_top = 0x10000000
		program_stack_virtual_address_bottom = program_stack_virtual_address_top - program_initial_stack_size
		program_stack_mapping = MemoryMapping.new(program_stack_virtual_address_bottom, program_stack_physical_address_bottom, program_initial_stack_size)

		# Zero out the process stack
		mapped_stack_bottom = mapper.map_kernel_region(program_stack_physical_address_bottom as link, program_initial_stack_size)
		global.memory.zero(mapped_stack_bottom, program_initial_stack_size as u64)

		# Allocate kernel stack for the process.
		# We need to allocate separate kernel stack for each thread as the execution might stop in kernel mode and we need to save the state.
		# Todo: Create stack quards here as well (proper stack support)

		if memory.kernel_stack_pointer === none {
			allocate_kernel_stack(memory)
		} else {
			debug.write_line('Process: Reusing kernel stack')
		}

		debug.write('Process: Arguments: ')
		debug.write_line(arguments)
		debug.write('Process: Environment variables: ')
		debug.write_line(environment_variables)

		startup_data_size = load_stack_startup_data(program_stack_physical_address_top, program_stack_virtual_address_top, arguments, environment_variables)
		program_stack_pointer = program_stack_virtual_address_top - startup_data_size

		# Map the process stack memory for the application
		memory.paging_table.map_region(allocator, program_stack_mapping, MAP_USER)

		# Register the stack to the process
		register_state[].userspace_rsp = program_stack_pointer
	}

	# Summary: Creates a process from the specified executable file
	shared from_executable(allocator: Allocator, file: Array<u8>, arguments: List<String>, environment_variables: List<String>): Process {
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
		user_frame: RegisterState* = allocator.allocate<RegisterState>()
		user_fpu_state: RegisterState* = allocator.allocate(PAGE_SIZE)
		kernel_frame: RegisterState* = allocator.allocate<RegisterState>()
		kernel_fpu_state: RegisterState* = allocator.allocate(PAGE_SIZE)
		configure_process_before_startup(allocator, user_frame, memory, load_information, arguments, environment_variables)

		# Attach the standard files for the new process
		file_descriptors: ProcessFileDescriptors = ProcessFileDescriptors(allocator, 256) using allocator
		attach_standard_files(allocator, file_descriptors)

		process = Process(user_frame, user_fpu_state, kernel_frame, kernel_fpu_state, memory, file_descriptors) using allocator
		process.working_directory = String.new('/bin/')

		return process
	}

	id: u64
	priority: u16 = NORMAL_PRIORITY

	# Summary: Stores the register state of userspace
	private user_frame: RegisterState*
	private user_fpu_state: link

	# Summary: Stores the register state of the thread when it stops in the kernel
	private kernel_frame: RegisterState*
	private kernel_fpu_state: link

	# Summary: Tells how many register states has been saved
	private frame_count: u8 = 1

	fs: u64 = 0 # Todo: Group with registers?
	memory: ProcessMemory
	file_descriptors: ProcessFileDescriptors
	working_directory: String
	credentials: Credentials
	blocker: Blocker
	readable state: u32
	parent: Process = none as Process
	childs: List<Process>
	is_kernel_process: bool = false
	is_sharing_parent_resources: bool = false
	subscribers: Subscribers

	is_running => state == THREAD_STATE_RUNNING
	is_blocked => state == THREAD_STATE_BLOCKED
	is_sleeping => state == THREAD_STATE_SLEEPING
	is_terminated => state == THREAD_STATE_TERMINATED

	registers => user_frame

	init(user_frame: RegisterState*, user_fpu_state: link, kernel_frame: RegisterState*, kernel_fpu_state: link, memory: ProcessMemory, file_descriptors: ProcessFileDescriptors) {
		this.id = 0
		this.user_frame = user_frame
		this.user_fpu_state = user_fpu_state
		this.kernel_frame = kernel_frame
		this.kernel_fpu_state = kernel_fpu_state
		this.memory = memory
		this.file_descriptors = file_descriptors
		this.working_directory = String.empty
		this.childs = List<Process>(HeapAllocator.instance) using HeapAllocator.instance
		this.subscribers = Subscribers.new(HeapAllocator.instance)

		registers[].cs = USER_CODE_SELECTOR | 3
		registers[].rflags = RFLAGS_INTERRUPT_FLAG
		registers[].userspace_ss = USER_DATA_SELECTOR | 3
	}

	# Summary: Saves the register state of the thread
	save(frame: RegisterState*): RegisterState* {
		require(frame_count < 2, 'Attempted to save register state more than twice')

		if frame_count++ == 1 {
			# Process should not save userspace state twice.
			# Note: Process can save userspace state and stop in kernel space
			is_kernel_space = (frame[].rip as i64) < 0
			require(is_kernel_space, 'Attempted to save userspace frame twice')

			# Save the kernel frame
			debug.write('Process: Saving kernel frame of process ') debug.write_line(id)
			kernel_frame[] = frame[]
			save_fpu_state(kernel_fpu_state)
			return kernel_frame
		}

		debug.write('Process: Saving user frame of process ') debug.write_line(id)
		user_frame[] = frame[]
		save_fpu_state(user_fpu_state)
		return user_frame
	}

	# Summary: Loads the register state of the thread into the specified frame
	load(frame: RegisterState*): _ {
		require(frame_count > 0, 'Attempted to load register state before saving')

		if frame_count-- == 2 {
			# Load the kernel frame into the specified frame
			debug.write('Process: Loading kernel frame of process ') debug.write_line(id)

			frame[] = kernel_frame[]
			load_fpu_state(kernel_fpu_state)
			return
		}

		# Load the user frame into the specified frame
		debug.write('Process: Loading user frame of process ') debug.write_line(id)
		frame[] = user_frame[]
		load_fpu_state(user_fpu_state)
	}

	# Summary: Loads the specified program into this process
	load(allocator: Allocator, file: Array<u8>, arguments: List<String>, environment_variables: List<String>): i32 {
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

		# Reset all the registers
		registers[] = 0 as RegisterState
		registers[].cs = USER_CODE_SELECTOR | 3
		registers[].rflags = RFLAGS_INTERRUPT_FLAG
		registers[].userspace_ss = USER_DATA_SELECTOR | 3

		# Allocate register state for the process so that we can configure the registers before starting
		configure_process_before_startup(allocator, registers, memory, load_information, arguments, environment_variables)
		return 0
	}

	# Summary: Blocks the process
	block(blocker: Blocker): _ {
		debug.write_line('Process: Blocking...')

		require(this.blocker === none and state == THREAD_STATE_RUNNING, 'Invalid thread state')
		require(blocker !== none, 'Attempted to block with no blocker')
		this.blocker = blocker
		this.blocker.process = this

		interrupts.scheduler.change_process_state(this, THREAD_STATE_BLOCKED)
	}

	# Summary: Unblocks the process
	unblock(): _ {
		debug.write_line('Process: Unblocking...')

		require(this.blocker !== none and state == THREAD_STATE_BLOCKED, 'Invalid thread state')
		this.blocker.process = none as Process
		this.blocker = none as Blocker

		interrupts.scheduler.change_process_state(this, THREAD_STATE_RUNNING)
	}

	subscribe(subscriber: Blocker): _ { subscribers.subscribe(subscriber) }
	unsubscribe(subscriber: Blocker): _ { subscribers.unsubscribe(subscriber) }

	# Summary: Changes the state of this process and notifies the subscribers as well
	change_state(state: u32): _ {
		this.state = state
		subscribers.update()
	}

	# Summary: Creates a child process that shares the resources of this process
	create_child_with_shared_resources(allocator: Allocator): Process {
		# Clone the registers from this process
		user_frame: RegisterState* = allocator.allocate<RegisterState>()
		user_fpu_state: link = allocator.allocate(PAGE_SIZE)
		kernel_frame: RegisterState* = allocator.allocate<RegisterState>()
		kernel_fpu_state: link = allocator.allocate(PAGE_SIZE)
		user_frame[] = this.user_frame[]
		global.memory.copy(user_fpu_state, this.user_fpu_state, PAGE_SIZE)

		# Clone the parent memory for sharing, but use a separate kernel stack
		child_memory = ProcessMemory(memory) using allocator
		allocate_kernel_stack(child_memory)

		# Create a new child process with the same resources and state
		child = Process(user_frame, user_fpu_state, kernel_frame, kernel_fpu_state, child_memory, file_descriptors) using allocator
		child.priority = priority
		child.working_directory = working_directory
		child.credentials = credentials

		# Set the parent of the child process
		child.parent = this
		child.is_sharing_parent_resources = true

		# Add the new process to the list of child processes
		childs.add(child)

		return child
	}

	# Summary: Detaches parent resources and creates new resources for this process
	detach_parent_resources(allocator: Allocator) {
		# Create paging tables for the process so that it can access memory correctly
		kernel_stack_pointer = memory.kernel_stack_pointer
		memory = ProcessMemory(allocator) using allocator
		memory.kernel_stack_pointer = kernel_stack_pointer

		file_descriptors = file_descriptors.clone()

		# Now we no longer use the parent resources
		is_sharing_parent_resources = false
		subscribers.update()
	}

	destruct(allocator: Allocator): _ {
		# Remove the process from the list of child processes
		if parent !== none {
			parent.childs.remove(this)
		}

		# If we have child processes, we need to detach them
		if childs.size > 0 {
			# - If they are sharing resources, we need to detach them
			# - Set their parent pointers to none
			panic('Todo')
		}

		# Dispose the register state
		if registers !== none KernelHeap.deallocate(registers)

		# Destruct the process memory
		if memory !== none {
			memory.destruct()
		}

		childs.destruct()
		subscribers.destruct()

		allocator.deallocate(this as link)
	}
}