namespace kernel.system_calls

# System call: execve
export system_execve(path_argument: link, arguments: link*, environment_variables: link*): i32 {
	debug.write('System call: Execute: ')
	debug.write('path=') debug.write_address(path_argument)
	debug.write(', arguments=') debug.write_address(arguments)
	debug.write(', environment_variables=') debug.write_address(environment_variables)
	debug.write_line()

	process = get_process()
	allocator = LocalHeapAllocator(HeapAllocator.instance)

	# Load the path argument into a string object
	if load_string(allocator, process, path_argument, PATH_MAX) has not path {
		debug.write_line('System call: Execute: Invalid path argument')
		allocator.deallocate()
		return EFAULT
	}

	# Count the number of arguments and environment variables so that we can load them
	arguments_count = count<link>(process, arguments, MAX_ARGUMENTS)

	if arguments_count < 0 {
		debug.write_line('System call: Execute: Invalid arguments')
		allocator.deallocate()
		return EFAULT
	}

	environment_variable_count = count<link>(process, environment_variables, MAX_ENVIRONMENT_VARIABLES)

	if environment_variable_count < 0 {
		debug.write_line('System call: Execute: Invalid environment variables')
		allocator.deallocate()
		return EFAULT
	}

	# Load them into lists
	argument_list = List<String>(allocator, arguments_count, false)
	if not load_strings(allocator, process, argument_list, arguments, arguments_count) return false

	environment_variable_list = List<String>(allocator, environment_variable_count, false)
	if not load_strings(allocator, process, environment_variable_list, environment_variables, environment_variable_count) return false

	result = system_execve(path, argument_list, environment_variable_list)

	allocator.deallocate()
	return result
}

# System call: execve
export system_execve(path: String, arguments: List<String>, environment_variables: List<String>): i32 {
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
	load_result = process.load(HeapAllocator.instance, program, arguments, environment_variables)

	# Deallocate the program buffer
	allocator.deallocate()

	return load_result
}