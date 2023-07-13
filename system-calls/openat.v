namespace kernel.system_calls

# System call: openat
export system_openat(directory_descriptor: i32, filename_argument: link, flags: u32, mode: u64): i32 {
	debug.write('System call: Open at: ')
	debug.write('directory_descriptor=') debug.write(directory_descriptor)
	debug.write(', filename=') debug.write_address(filename_argument)
	debug.write(', flags=') debug.write_address(flags)
	debug.write(', mode=') debug.write(mode)
	debug.write_line()

	process = get_process()
	allocator = BufferAllocator(buffer: u8[PATH_MAX], PATH_MAX)

	# Load the filename argument into a string object
	if load_string(allocator, process, filename_argument, PATH_MAX) has not filename {
		debug.write_line('System call: Open at: Invalid filename argument')
		return EFAULT
	}

	# If the specified path is absolute, just use open system call
	if filename.starts_with(`/`) return system_open(process, filename, flags, mode)

	local_allocator = LocalHeapAllocator(HeapAllocator.instance)

	# Figure out the custody of the specified directory, so that we can look for the file
	custody = none as Custody

	# Todo: Duplicate?
	if filename.starts_with(`/`) {
		custody = Custody.root
	} else directory_descriptor == AT_FDCWD {
		# User wants we to use the current working directory of the process
		custody = FileSystem.root.open_path(local_allocator, Custody.root, process.working_directory, 0).value_or(none as Custody)
	} else {
		# Find the directory description associated with the specified descriptor
		directory_description = process.file_descriptors.try_get_description(directory_descriptor)

		if directory_description === none {
			debug.write_line('System call: Open at: Invalid directory descriptor')
			return EBADF
		}

		# Ensure the description represents a directory
		if not directory_description.is_directory return ENOTDIR

		custody = directory_description.custody
	}

	# Abort if we failed to get the custody
	if custody === none {
		debug.write_line('System call: Open at: Failed to open the path')
		local_allocator.deallocate()
		return EINVAL
	}

	return system_openat(local_allocator, get_process(), custody, filename, flags, mode)
}

# System call: openat
export system_openat(allocator, process: Process, custody: Custody, filename: String, flags: u32, mode: u64): i32 {	
	# First, try allocating a file descriptor before doing anything
	if process.file_descriptors.allocate() has not descriptor {
		debug.write_line('System call: Open at: Failed to allocate a file descriptor')
		allocator.deallocate()
		return ENOMEM
	}

	# Try opening the specified path as a file from the specified custody
	result = FileSystem.root.open_file(custody, filename, flags, mode)

	if result has not description {
		debug.write_line('System call: Open at: Failed to open the specified filename')
		allocator.deallocate()
		return result.error
	}

	require(process.file_descriptors.attach(descriptor, description), 'Failed to attach file description to descriptor')

	debug.write('System call: Open at: Opening succeeded, returning descriptor ') debug.write_line(descriptor)
	return descriptor
}