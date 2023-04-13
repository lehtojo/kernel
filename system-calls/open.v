namespace kernel.system_calls

import kernel.file_systems

constant PATH_MAX = 256

# System call: open
export system_open(path_argument: link, flags: i32, mode: u32): i32 {
	debug.write('System call: Open: ')
	debug.write('path=') debug.write_address(path_argument)
	debug.write(', flags=') debug.write_address(flags)
	debug.write(', mode=') debug.write(mode)
	debug.write_line()

	process = get_process()
	allocator = BufferAllocator(buffer: u8[PATH_MAX], PATH_MAX)

	# Load the path argument into a string object
	if load_string(allocator, process, path_argument, PATH_MAX) has not path {
		debug.write_line('System call: Open: Invalid path argument')
		return EFAULT
	}

	return system_open(get_process(), path, flags, mode)
}

# System call: open
export system_open(process: Process, path: String, flags: i32, mode: u32): i32 {
	# First, try allocating a file descriptor before doing anything
	if process.file_descriptors.allocate() has not descriptor {
		debug.write_line('System call: Open: Failed to allocate a file descriptor')
		return ENOMEM
	}

	# Try opening the specified path as a file
	result = FileSystem.root.open_file(Custody.root, path, flags, mode)

	if result has not description {
		debug.write_line('System call: Open: Failed to open the specified path')
		return result.error
	}

	require(process.file_descriptors.attach(descriptor, description), 'Failed to attach file description to descriptor')
	return descriptor
}