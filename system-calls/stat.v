namespace kernel.system_calls

# System call: stat
export system_stat(path_argument: link, buffer: link): u32 {
	debug.write('System call: Stat: ')
	debug.write('path=') debug.write_address(path_argument)
	debug.write(', buffer=') debug.write_address(buffer)
	debug.write_line()

	process = get_process()
	allocator = BufferAllocator(allocator_buffer: u8[PATH_MAX], PATH_MAX)

	# Load the path argument into a string object
	if load_string(allocator, process, path_argument, PATH_MAX) has not path {
		debug.write_line('System call: Stat: Invalid path argument')
		return EFAULT
	}

	# Lookup the file status into the user buffer
	return FileSystem.root.lookup_status(Custody.root, path, buffer as FileMetadata)
}

# System call: fstat
export system_fstat(file_descriptor: u32, buffer: link): u32 {
	debug.write('System call: Fstat: ')
	debug.write('file_descriptor=') debug.write(file_descriptor)
	debug.write(', buffer=') debug.write_address(buffer)
	debug.write_line()

	process = get_process()

	# Try getting the file description associated with the specified descriptor
	file_description = process.file_descriptors.try_get_description(file_descriptor)

	if file_description === none {
		debug.write_line('System call: Fstat: Invalid file descriptor')
		return EBADF
	}

	# Load the file status into the user buffer
	return file_description.load_status(buffer as FileMetadata)
}

# System call: fstatat
export system_fstatat(directory_descriptor: u32, path_argument: link, buffer: link, flags: u32): u32 {
	debug.write('System call: Fstatat: ')
	debug.write('directory_descriptor=') debug.write(directory_descriptor)
	debug.write(', path=') debug.write_address(path_argument)
	debug.write(', buffer=') debug.write_address(buffer)
	debug.write(', flags=') debug.write(flags)
	debug.write_line()

	process = get_process()
	allocator = BufferAllocator(allocator_buffer: u8[PATH_MAX], PATH_MAX)

	# Load the path argument into a string object
	if load_string(allocator, process, path_argument, PATH_MAX) has not path {
		debug.write_line('System call: Fstatat: Invalid path argument')
		return EFAULT
	}

	# If the path is empty and AT_EMPTY_PATH is set, the system call behaves like fstat
	if has_flag(flags, AT_EMPTY_PATH) and path.length == 0 return system_fstat(directory_descriptor, buffer)

	# Output path as debugging information
	debug.write('System call: Fstatat: Path = ') debug.write_line(path)

	local_allocator = LocalHeapAllocator(HeapAllocator.instance)

	# Figure out the custody of the specified directory, so that we can look for the file
	# Note: Duplicated from openat system call
	custody = none as Custody

	if directory_descriptor == AT_FDCWD {
		# User wants we to use the current working directory of the process
		custody = FileSystem.root.open_path(local_allocator, Custody.root, process.working_directory, 0).value_or(none as Custody)
	} else {
		# Find the directory description associated with the specified descriptor
		directory_description = process.file_descriptors.try_get_description(directory_descriptor)

		if directory_description === none {
			debug.write_line('System call: Fstatat: Invalid directory descriptor')
			return EBADF
		}

		# Ensure the description represents a directory
		if not directory_description.is_directory return ENOTDIR

		custody = directory_description.custody
	}

	# Abort if we failed to get the custody
	if custody === none {
		local_allocator.deallocate()
		return EINVAL
	}

	# Lookup the file status into the user buffer
	result = FileSystem.root.lookup_status(custody, path, buffer as FileMetadata)
	
	local_allocator.deallocate()
	return result
}