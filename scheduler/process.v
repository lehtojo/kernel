namespace kernel.scheduler

import kernel.file_systems
import kernel.elf.loader
import kernel.devices.console

constant RFLAGS_INTERRUPT_FLAG = 1 <| 9

constant CLONE_VM = 1 <| 8
constant CLONE_FILES = 1 <| 10
constant CLONE_VFORK = 1 <| 14
constant CLONE_PARENT = 1 <| 15
constant CLONE_THREAD = 1 <| 16
constant CLONE_SETTLS = 1 <| 19
constant CLONE_PARENT_SETTID = 1 <| 20
constant CLONE_CHILD_CLEARTID = 1 <| 21
constant CLONE_CHILD_SETTID = 1 <| 24
constant CLONE_NEWPID = 1 <| 29

plain CloneArguments {
	flags: u64
	pid_file_descriptor: u64
	child_tid: u64
	parent_tid: u64
	exit_signal: u64
	stack: u64
	stack_size: u64
	tls: u64
	set_tid: u64
	set_tid_size: u64
	control_group: u64
}

pack ThreadEvents {
	set_child_tid: u32*
	clear_child_tid: u32*

	shared new(): ThreadEvents {
		return pack {
			set_child_tid: none as u32*,
			clear_child_tid: none as u32*
		} as ThreadEvents
	}
}

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

			options = ProcessMemoryRegionOptions.new()

			if allocation.type == PROCESS_ALLOCATION_PROGRAM_TEXT {
				options.flags |= REGION_EXECUTABLE
			}

			# Reserve the allocation from the process memory
			# When the process is destroyed, the allocation list is used to deallocate the memory.
			memory.add_allocation(allocation.type, ProcessMemoryRegion.new(allocation, options))

			# Set the program break after all loaded segments
			memory.state.break = math.max(memory.state.break, allocation.end as u64)
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
		global.memory.zero(user_fpu_state, PAGE_SIZE)
		global.memory.zero(kernel_fpu_state, PAGE_SIZE)

		configure_process_before_startup(allocator, user_frame, memory, load_information, arguments, environment_variables)

		# Attach the standard files for the new process
		file_descriptors: ProcessFileDescriptors = ProcessFileDescriptors(allocator, 256) using allocator
		attach_standard_files(allocator, file_descriptors)

		process = Process(user_frame, user_fpu_state, kernel_frame, kernel_fpu_state, memory, file_descriptors) using allocator
		process.working_directory = String.new('/bin/')

		return process
	}

	pid: u64
	tid: u64
	priority: u16 = NORMAL_PRIORITY

	# Summary: Stores the register state of userspace
	private user_frame: RegisterState*
	private user_fpu_state: link

	# Summary: Stores the register state of the thread when it stops in the kernel
	private kernel_frame: RegisterState*
	private kernel_fpu_state: link

	# Summary: Tells how many register states has been saved
	private frame_count: u8 = 1

	# Stores which CPUs are allowed to execute this process
	affinity: u64
	fs: u64 = 0 # Todo: Group with registers?
	memory: ProcessMemory
	file_descriptors: ProcessFileDescriptors
	working_directory: String
	credentials: Credentials
	blocker: Blocker
	events: ThreadEvents
	readable state: u32
	parent: Process = none as Process
	childs: List<Process>
	is_kernel_process: bool = false
	is_borrowing_parent_resources: bool = false
	subscribers: Subscribers

	is_running => state == THREAD_STATE_RUNNING
	is_blocked => state == THREAD_STATE_BLOCKED
	is_sleeping => state == THREAD_STATE_SLEEPING
	is_terminated => state == THREAD_STATE_TERMINATED

	registers => user_frame

	init(user_frame: RegisterState*, user_fpu_state: link, kernel_frame: RegisterState*, kernel_fpu_state: link, memory: ProcessMemory, file_descriptors: ProcessFileDescriptors) {
		this.pid = 0
		this.tid = 0
		this.user_frame = user_frame
		this.user_fpu_state = user_fpu_state
		this.kernel_frame = kernel_frame
		this.kernel_fpu_state = kernel_fpu_state
		# Todo: We're don't support SMP yet
		this.affinity = 1
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
			kernel_frame[] = frame[]
			save_fpu_state(kernel_fpu_state)

			debug.write('Process: Saved kernel frame of process ') debug.write_line(tid)
			return kernel_frame
		}

		user_frame[] = frame[]
		save_fpu_state(user_fpu_state)

		debug.write('Process: Saved user frame of process ') debug.write_line(tid)
		return user_frame
	}

	# Summary: Loads the register state of the thread into the specified frame
	load(frame: RegisterState*): _ {
		require(frame_count > 0, 'Attempted to load register state before saving')

		if frame_count-- == 2 {
			# Load the kernel frame into the specified frame
			debug.write('Process: Loading kernel frame of process ') debug.write(tid)
			debug.write(' (rip=') debug.write_address(kernel_frame[].rip) debug.write_line(')')

			frame[] = kernel_frame[]
			load_fpu_state(kernel_fpu_state)
			return
		}

		# Load the user frame into the specified frame
		debug.write('Process: Loading user frame of process ') debug.write(tid)
		debug.write(' (rip=') debug.write_address(user_frame[].rip) debug.write_line(')')

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

	clone(allocator: Allocator, arguments: CloneArguments): Result<Process, i64> {
		# Clone the registers from this process
		user_frame: RegisterState* = allocator.allocate<RegisterState>()
		user_fpu_state: link = allocator.allocate(PAGE_SIZE)
		kernel_frame: RegisterState* = allocator.allocate<RegisterState>()
		kernel_fpu_state: link = allocator.allocate(PAGE_SIZE)
		user_frame[] = this.user_frame[]
		global.memory.copy(user_fpu_state, this.user_fpu_state, PAGE_SIZE)
		global.memory.zero(kernel_fpu_state, PAGE_SIZE)

		# Stack:
		if arguments.stack !== none {
			debug.write_line('Process: Clone: Using a separate stack')

			stack_address = arguments.stack

			debug.write('Process: Using stack at address ') debug.write_address(stack_address)
			debug.write(' with size of ') debug.write(arguments.stack_size) debug.write_line(' bytes')

			# Verify the stack is correctly aligned
			if not global.memory.is_aligned(stack_address, 16) {
				debug.write_line('Process: Clone: Stack is not aligned correctly')
				return Results.error<Process, i64>(EINVAL)
			}

			user_frame[].userspace_rsp = stack_address + PAGE_SIZE
			# Todo: Once we have proper stack support, take the stack size into account
		}

		# Memory:
		child_memory = none as ProcessMemory

		if has_flag(arguments.flags, CLONE_VM) {
			child_memory = ProcessMemory(memory) using allocator
			allocate_kernel_stack(child_memory)
		} else {
			debug.write_line('Process: Clone: Cloning with out CLONE_VM flag is not supported')
			return Results.error<Process, u64>(ENOTSUP)
		}

		# File descriptors:
		# Todo: As with other process resources, we need reference counting, because exiting threads can not just deallocate shared resources
		child_file_descriptors = file_descriptors

		if not has_flag(arguments.flags, CLONE_FILES) {
			debug.write_line('Process: Clone: Copying file descriptors')
			child_file_descriptors = ProcessFileDescriptors(file_descriptors) using allocator
		}

		# Create a new child process with the same resources and state
		child = Process(user_frame, user_fpu_state, kernel_frame, kernel_fpu_state, child_memory, child_file_descriptors) using allocator
		child.fs = fs
		child.priority = priority
		child.working_directory = working_directory
		child.credentials = credentials

		# Determine the parent of the new process
		if has_flag(arguments.flags, CLONE_PARENT) {
			debug.write_line('Process: Clone: Using parent of calling process as the parent of the new process')

			if parent === none {
				debug.write_line('Process: Clone: Can not create two root processes')
				return Results.error<Process, u64>(EINVAL)
			}

			child.parent = parent
			parent.childs.add(child)
		} else {
			child.parent = this
			childs.add(child)
		}

		# TLS:
		if has_flag(arguments.flags, CLONE_SETTLS) {
			debug.write('Process: Clone: Setting TLS to ') debug.write_address(arguments.tls) debug.write_line()
			child.fs = arguments.tls
		}

		# PID:
		if has_flag(arguments.flags, CLONE_NEWPID) {
			if has_flag(arguments.flags, CLONE_THREAD) or has_flag(arguments.flags, CLONE_PARENT) {
				debug.write_line('Process: Clone: Can not assign a new pid when CLONE_THREAD or CLONE_PARENT is set')
			}
		} else {
			child.pid = child.parent.pid
		}

		if has_flag(arguments.flags, CLONE_VFORK) {
			debug.write_line('Process: Clone: Borrowing parent resources (vfork)')
			child.is_borrowing_parent_resources = true
		}

		if has_flag(arguments.flags, CLONE_CHILD_CLEARTID) {
			debug.write('Process: Clone: Clear child TID = ')
			debug.write_address(arguments.child_tid)
			debug.write_line()

			child.events.clear_child_tid = arguments.child_tid as u32*
		}

		return Results.new<Process, u64>(child)
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
		global.memory.zero(kernel_fpu_state, PAGE_SIZE)

		# Clone the parent memory for sharing, but use a separate kernel stack
		child_memory = ProcessMemory(memory) using allocator
		allocate_kernel_stack(child_memory)

		# Create a new child process with the same resources and state
		child = Process(user_frame, user_fpu_state, kernel_frame, kernel_fpu_state, child_memory, file_descriptors) using allocator
		child.fs = fs
		child.priority = priority
		child.working_directory = working_directory
		child.credentials = credentials

		# Set the parent of the child process
		child.parent = this
		child.is_borrowing_parent_resources = true

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
		is_borrowing_parent_resources = false
		subscribers.update()
	}

	execute_destruct_events(): _ {
		if events.clear_child_tid !== none and 
			is_valid_region(this, events.clear_child_tid, sizeof(u32), true) {

			events.clear_child_tid[] = 0
			Futexes.wake(events.clear_child_tid as u64)
		}
	}

	destruct(allocator: Allocator): _ {
		execute_destruct_events()

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
