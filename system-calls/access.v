namespace kernel.system_calls

# System call: access
export system_access(path_argument: link, mode: u64): i64 {
	debug.write('System call: Access: ')
	debug.write('path=') debug.write_address(path_argument)
	debug.write(', mode=') debug.write(mode)
	debug.write_line()

	allocator = BufferAllocator(buffer: u8[PATH_MAX], PATH_MAX)

	# Load the path argument into a string object
	if load_string(allocator, path_argument, PATH_MAX) has not path {
		debug.write_line('System call: Access: Invalid path argument')
		return EFAULT
	}

	# Attempt to access the specified path in the specified mode
	return FileSystem.root.access(Custody.root, path, mode)
}