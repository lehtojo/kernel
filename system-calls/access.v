namespace kernel.system_calls

# System call: access
export system_access(path_argument: link, mode: u64): i64 {
	debug.write('System call: Access: ')
	debug.write('path=') debug.write_address(path_argument)
	debug.write(', mode=') debug.write(mode)
	debug.write_line()

	process = get_process()
	allocator = BufferAllocator(buffer: u8[PATH_MAX], PATH_MAX)

	# Load the path argument into a string object
	if load_string(allocator, process, path_argument, PATH_MAX) has not path {
		debug.write_line('System call: Access: Invalid path argument')
		return EFAULT
	}

	# Attempt to access the specified path in the specified mode
	return FileSystem.root.access(Custody.root, path, mode)
}

# System call: faccessat
export system_faccessat(directory_descriptor: u64, path_argument: link, mode: u64): i64 {
	debug.write('System call: Faccessat: ')
	debug.write('directory_descriptor=') debug.write(directory_descriptor)
	debug.write(', path=') debug.write(path_argument)
	debug.write(', mode=') debug.write(mode)
	debug.write_line()

	process = get_process()
	allocator = LocalHeapAllocator(HeapAllocator.instance)

	# Load the path argument into a string object
	if load_string(allocator, process, path_argument, PATH_MAX) has not path {
		debug.write_line('System call: Faccessat: Invalid path argument')
		return EFAULT
	}

	# Figure out the custody of the specified directory, so that we can look for the file
	# Note: Duplicated from openat system call
	custody = none as Custody

	# Todo: Duplicate?
	if path.starts_with(`/`) {
		custody = Custody.root
	} else directory_descriptor == AT_FDCWD {
		# User wants we to use the current working directory of the process
		custody = FileSystem.root.open_path(allocator, Custody.root, process.working_directory, 0).value_or(none as Custody)
	} else {
		# Find the directory description associated with the specified descriptor
		directory_description = process.file_descriptors.try_get_description(directory_descriptor)

		if directory_description === none {
			debug.write_line('System call: Faccessat: Invalid directory descriptor')
			return EBADF
		}

		# Ensure the description represents a directory
		if not directory_description.is_directory return ENOTDIR

		custody = directory_description.custody
	}

	# Abort if we failed to get the custody
	if custody === none {
		allocator.deallocate()
		return EINVAL
	}

	# Attempt to access the specified path in the specified mode
	return FileSystem.root.access(custody, path, mode)
}