namespace kernel.scheduler

constant THREAD_STATE_RUNNING = 0
constant THREAD_STATE_BLOCKED = 1
constant THREAD_STATE_SLEEPING = 2
constant THREAD_STATE_TERMINATED = 3

pack SchedulerProcesses {
	running: List<Process>
	blocked: List<Process>

	add(process: Process): _ {
		if process.state == THREAD_STATE_RUNNING {
			debug.write('Scheduler: Process ') debug.write(process.tid) debug.write_line(' is running')
			running.add(process)
		} else process.state == THREAD_STATE_BLOCKED {
			debug.write('Scheduler: Process ') debug.write(process.tid) debug.write_line(' is blocked')
			blocked.add(process)
		} else {
			panic('Invalid process state')
		}
	}

	remove(process: Process): bool {
		debug.write('Scheduler: Removing process ') debug.write_line(process.tid)
		return running.remove(process) or blocked.remove(process)
	}

   size(): u64 {
      return running.size + blocked.size
   }
}

Scheduler {
	current: Process = none as Process
	processes: SchedulerProcesses
	next_id: u32

	init() {
		this.next_id = 1
	}

	initialize_processes() {
		this.processes.running = List<Process>(HeapAllocator.instance, 256, false) using KernelHeap
		this.processes.blocked = List<Process>(HeapAllocator.instance, 256, false) using KernelHeap
	}

	# Summary: Adds the specified process to the running process list and gives it a new pid and tid
	add_process(process: Process) {
		process.pid = next_id
		process.tid = next_id++
		processes.running.add(process)
	}

	# Summary: Adds the specified process to the running process list and gives it a new tid
	add_thread(process: Process) {
		process.tid = next_id++
		processes.running.add(process)
	}

	# Summary: Attempts to find a process by the specified pid
	find(pid: u32): Optional<Process> {
		loop (i = 0, i < processes.running.size, i++) {
			process = processes.running[i]
			if process.pid == pid and (process.parent === none or process.parent.pid != pid) return Optionals.new<Process>(process)
		}

		loop (i = 0, i < processes.blocked.size, i++) {
			process = processes.blocked[i]
			if process.pid == pid and (process.parent === none or process.parent.pid != pid) return Optionals.new<Process>(process)
		}

		return Optionals.empty<Process>()
	}

	change_process_state(process: Process, to: u32): _ {
		processes.remove(process)
		process.change_state(to)
		processes.add(process)
	}

	pick(): Process {
		result = processes.running[0]
		processes.running.remove_at(0)
		processes.running.add(result)

		return result
	}

	yield(): _ {
		debug.write('Scheduler: Yielding process ') debug.write_line(current.tid)

		# Save the current state and the next time this thread is ready it will continue from here in kernel mode
		# System call: sched_yield

		# Switch to general kernel stack, so that the system call will not modify the current stack
		Processor.current.kernel_stack_pointer = Processor.current.general_kernel_stack_pointer

		system_call(0x18, 0, 0, 0, 0, 0, 0)
	}

	switch(frame: RegisterState*, next: Process) {
		debug.write('Scheduler: Switching to process ')
		debug.write(next.tid)
		debug.write(' (rip=')
		debug.write_address(next.registers[].rip)
		debug.write_line(')')

		# Update fs register
		enable_general_purpose_segment_instructions()
		write_fs_base(next.fs)
		disable_general_purpose_segment_instructions()

		# Update the kernel stack pointer
		Processor.current.kernel_stack_pointer = next.memory.kernel_stack_pointer as link
		require(Processor.current.kernel_stack_pointer !== none, 'Missing thread kernel stack pointer')

		current = next

		# Map the process to memory
		if next.memory !== none next.memory.paging_table.use()
	}

	enter(frame: RegisterState*, next: Process) {
		debug.write('Scheduler: Entering to process ')
		debug.write_line(next.tid)

		if current !== next switch(frame, next)
	}

	pick_and_enter(frame: RegisterState*) {
		# Choose the next process to execute
		next = pick()
		if next === none return

		# Switch to the next process
		enter(frame, next)
	}

	tick(frame: RegisterState*): _ {
		is_kernel_space = (frame[].rip as i64) < 0
		is_interrupts_enabled = (frame[].rflags & RFLAGS_INTERRUPT_FLAG) != 0
		require(is_interrupts_enabled or is_kernel_space, 'Illegal flags-register')

		# Todo: Verify IOPL and RSP

		pick_and_enter(frame)
	}

	exit(frame: RegisterState*, process: Process) {
		debug.write('Scheduler: Exiting process ') debug.write_line(process.tid)
		process.change_state(THREAD_STATE_TERMINATED)

		# Remove the specified process from the process list
		require(processes.remove(process), 'Attempted to exit a process that was not in the process list')

		debug.write('Scheduler: Destructing process ') debug.write_line(process.tid)
		process.destruct(HeapAllocator.instance)

		debug.write_line('Scheduler: Picking next process after exiting process')
		pick_and_enter(frame)
	}
}

create_kernel_thread(rip: u64): Process {
	debug.write_line('Scheduler: Creating a kernel thread...')

	user_frame: RegisterState* = KernelHeap.allocate<RegisterState>()
	user_fpu_state: RegisterState* = KernelHeap.allocate(PAGE_SIZE)
	kernel_frame: RegisterState* = KernelHeap.allocate<RegisterState>()
	kernel_fpu_state: RegisterState* = KernelHeap.allocate(PAGE_SIZE)
	global.memory.zero(user_fpu_state, PAGE_SIZE)
	global.memory.zero(kernel_fpu_state, PAGE_SIZE)

	memory = ProcessMemory(HeapAllocator.instance) using KernelHeap

	# Allocate stacks for the process.
	# We need to allocate separate kernel stack for each thread as the execution might stop in kernel mode and we need to save the state.
	# Todo: Create stack quards here as well (proper stack support)
	debug.write_line('Scheduler: Allocating kernel thread stack...')
	user_stack_pointer = KernelHeap.allocate(512 * KiB)
	kernel_stack_pointer = KernelHeap.allocate(512 * KiB)

	# Zero out the stack memory
	global.memory.zero(kernel_stack_pointer, 512 * KiB)

	# Store the kernel stack pointer for use
	memory.kernel_stack_pointer = (kernel_stack_pointer + 512 * KiB) as u64

	file_descriptors = ProcessFileDescriptors(HeapAllocator.instance, 256) using KernelHeap

	process = Process(user_frame, user_fpu_state, kernel_frame, kernel_fpu_state, memory, file_descriptors) using KernelHeap
	process.registers[].cs = USER_CODE_SELECTOR
	process.registers[].rflags = 0
	process.registers[].userspace_ss = USER_DATA_SELECTOR
	process.registers[].rip = rip
	process.registers[].userspace_rsp = (user_stack_pointer + 512 * KiB) as u64

	interrupts.scheduler.add_process(process)

	return process
}

create_idle_process(): Process {
	debug.write_line('Scheduler: Creating an idle process...')

	user_frame: RegisterState* = KernelHeap.allocate<RegisterState>()
	user_fpu_state: RegisterState* = KernelHeap.allocate(PAGE_SIZE)
	kernel_frame: RegisterState* = KernelHeap.allocate<RegisterState>()
	kernel_fpu_state: RegisterState* = KernelHeap.allocate(PAGE_SIZE)
	global.memory.zero(user_fpu_state, PAGE_SIZE)
	global.memory.zero(kernel_fpu_state, PAGE_SIZE)

	memory = ProcessMemory(HeapAllocator.instance) using KernelHeap

	# Allocate a page for the text section that will just loop forever
	debug.write_line('Scheduler: Allocating text section for an idle process...')

	text_section_physical_address = PhysicalMemoryManager.instance.allocate_physical_region(PAGE_SIZE)
	require(text_section_physical_address !== none, 'Failed to allocate physical memory for an idle process')

	if memory.allocate_region_anywhere(ProcessMemoryRegionOptions.new(), PAGE_SIZE, PAGE_SIZE) has not text_section_virtual_address {
		panic('Failed to allocate virtual text section memory for an idle process')
	}

	# Initialize the text section:
	# start:
	# jmp start
	mapped_text_section = mapper.map_kernel_page(text_section_physical_address)
	global.memory.zero(mapped_text_section, PAGE_SIZE)
	mapped_text_section[0] = 0xeb
	mapped_text_section[1] = 0xfe

	# Map the physical memory to the allocated virtual memory
	memory.paging_table.map_page(HeapAllocator.instance, text_section_virtual_address as link, text_section_physical_address, MAP_USER | MAP_EXECUTABLE)

	# Allocate stacks for the process.
	# We need to allocate separate kernel stack for each thread as the execution might stop in kernel mode and we need to save the state.
	# Todo: Create stack quards here as well (proper stack support)
	debug.write_line('Scheduler: Allocating idle process stacks...')

	user_stack_physical_address = PhysicalMemoryManager.instance.allocate_physical_region(PAGE_SIZE)
	require(user_stack_physical_address !== none, 'Failed to allocate physical memory for an idle process')

	if memory.allocate_region_anywhere(ProcessMemoryRegionOptions.new(), PAGE_SIZE, PAGE_SIZE) has not user_stack_bottom {
		panic('Failed to allocate virtual stack memory for an idle process')
	}

	# Map the physical memory to the allocated virtual memory
	memory.paging_table.map_page(HeapAllocator.instance, user_stack_bottom as link, user_stack_physical_address, MAP_USER)

	# Zero out the user stack
	mapped_user_stack = mapper.map_kernel_page(user_stack_physical_address)
	global.memory.zero(mapped_user_stack, PAGE_SIZE)

	kernel_stack_bottom = KernelHeap.allocate(PAGE_SIZE)
	require(kernel_stack_bottom !== none, 'Failed to allocate kernel stack for an idle process')

	# Zero out the stack memory
	global.memory.zero(kernel_stack_bottom, PAGE_SIZE)

	# Store the kernel stack pointer for use
	memory.kernel_stack_pointer = (kernel_stack_bottom + PAGE_SIZE) as u64

	file_descriptors = ProcessFileDescriptors(HeapAllocator.instance, 256) using KernelHeap

	process = Process(user_frame, user_fpu_state, kernel_frame, kernel_fpu_state, memory, file_descriptors) using KernelHeap
	process.registers[].rip = text_section_virtual_address
	process.registers[].userspace_rsp = (user_stack_bottom + PAGE_SIZE) as u64

	interrupts.scheduler.add_process(process)

	return process
}

# Summary: Attaches the specified console to the process
export attach_console_to_process(process: Process, console: Device): _ {
	# Replace the devices of standard input, output and error
	loop (file_descriptor = 0, file_descriptor <= 2, file_descriptor++) {
		file_description = process.file_descriptors.try_get_description(file_descriptor)
		require(file_description !== none, 'Process did not have required standard file')

		# Replace the device of the file description
		file_description.file = console
	}	
}

export create_boot_shell_process(allocator: Allocator, boot_console: BootConsoleDevice): _ {
	debug.write_line('Scheduler: Creating boot shell process...')

	runtime_linker_program = String.new('/lib/ld')
	shell_program = String.new('/bin/sh')

	runtime_linker_file_or_error = FileSystems.root.open_file(Custody.root, runtime_linker_program, O_RDONLY, 0)
	require(runtime_linker_file_or_error has runtime_linker_file, 'Failed to open the runtime linker file')

	debug.write_line('Scheduler: Loading the runtime linker into memory...')

	shell_size = runtime_linker_file.size
	debug.write('Scheduler: Size of the runtime linker = ') debug.write(shell_size) debug.write_line(' byte(s)')

	shell = allocator.allocate(shell_size)
	memory.zero(shell, shell_size)

	if shell === none {
		debug.write_line('Scheduler: Failed to allocate memory for the runtime linker')
		return
	}

	if runtime_linker_file.read(shell, shell_size) != shell_size {
		debug.write_line('Scheduler: Failed to read the runtime linker into memory')
		return
	}

	debug.write_line('Scheduler: Runtime linker is now loaded into memory')
	runtime_linker_file.close()

	arguments = List<String>(allocator)
	arguments.add(runtime_linker_program)
	arguments.add(shell_program)

	environment_variables = List<String>(allocator)
	environment_variables.add(String.new('PATH=/bin/:/lib/')) # Todo: Get proper PATH variable

	process = Process.from_executable(allocator, Array<u8>(shell, shell_size), arguments, environment_variables)

	# Remove all the arguments and environment variables, because they are no longer needed here
	arguments.clear()
	environment_variables.clear()

	if process === none panic('Scheduler: Failed to create the boot shell process')

	# Attach the boot console to the process
	attach_console_to_process(process, boot_console)

	debug.write_line('Scheduler: Boot shell process created')

	interrupts.scheduler.add_process(process)
}
