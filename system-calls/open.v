namespace kernel.system_calls

import kernel.file_systems

constant PATH_MAX = 256

# System call: open
export system_open(path_argument: link, flags: i32, mode: u32): i32 {
	allocator = BufferAllocator(buffer: u8[PATH_MAX], PATH_MAX)

	# Load the path argument into a string object
	if load_string(allocator, path_argument, PATH_MAX) has not path return EFAULT

	return system_open(get_process(), path, flags, mode)
}

# System call: open
export system_open(process: Process, path: String, flags: i32, mode: u32): i32 {
	# First, try allocating a file descriptor before doing anything
	if process.file_descriptors.allocate() has not descriptor return ENOMEM

	# Try opening the specified path as a file
	result = kernel.file_systems.FileSystem.root.open_file(kernel.file_systems.Custody.root, path, flags, mode)
	if result has not description return result.error

	require(process.file_descriptors.attach(descriptor, description), 'Failed to attach file description to descriptor')
	return descriptor
}