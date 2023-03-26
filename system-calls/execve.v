namespace kernel.system_calls

# System call: execve
export system_execve(path_argument: link, arguments: link, environment_variables: link): i32 {
	debug.write('System call: Execute: ')
	debug.write('path=') debug.write_address(path_argument)
	debug.write(', arguments=') debug.write_address(arguments)
	debug.write(', environment_variables=') debug.write_address(environment_variables)
	debug.write_line()

	allocator = BufferAllocator(buffer: u8[PATH_MAX], PATH_MAX)

	# Load the path argument into a string object
	if load_string(allocator, path_argument, PATH_MAX) has not path {
		debug.write_line('System call: Execute: Invalid path argument')
		return EFAULT
	}

	# Todo: Consider the arguments and environment variables
	return system_execve(path)
}

# System call: execve
export system_execve(path: String): i32 {
	process = get_process()

	# Remove all program allocations such as text and data sections
	process.memory.deallocate_program_allocations()

	# Open the program for loading
	# Todo: Fix the constants
	open_result = FileSystem.root.open_file(Custody.root, path, O_RDONLY, 0)
	if open_result has not description return open_result.error

	# Load the size of the program
	size = description.size

	# Todo: Do not load the whole program to memory. Load necessary parts only by seeking.
	allocator = LocalHeapAllocator(HeapAllocator.instance)
	program = Array<u8>(allocator, size)

	# Load the program into the buffer
	description.read(program.data, program.size)

	# Load the program into the process
	load_result = process.load(HeapAllocator.instance, program)

	# Deallocate the program buffer
	allocator.deallocate()

	return load_result
}