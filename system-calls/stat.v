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
	return FileSystems.root.lookup_status(Custody.root, path, buffer as FileMetadata)
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

# Todo: Duplicate
load_custody(allocator: Allocator, process: Process, directory_descriptor: u32, path: String): Result<Custody, u32> {
	# Figure out the custody of the specified directory, so that we can look for the file
	if path.starts_with(`/`) {
		return Results.new<Custody, u32>(Custody.root)
	} 

	if directory_descriptor == AT_FDCWD {
		# User wants we to use the current working directory of the process
		custody = FileSystems.root.open_path(allocator, Custody.root, process.working_directory, 0).value_or(none as Custody)
		if custody !== none return Results.new<Custody, u32>(custody)

		return Results.error<Custody, u32>(EINVAL)
	}

	# Find the directory description associated with the specified descriptor
	directory_description = process.file_descriptors.try_get_description(directory_descriptor)

	if directory_description === none {
		debug.write_line('System call: Fstatat: Invalid directory descriptor')
		return Results.error<Custody, u32>(EBADF)
	}

	# Ensure the description represents a directory
	if not directory_description.is_directory return Results.error<Custody, u32>(ENOTDIR)

	return Results.new<Custody, u32>(directory_description.custody)
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

	# Load the path argument into a string
	if load_string(allocator, process, path_argument, PATH_MAX) has not path {
		debug.write_line('System call: Fstatat: Invalid path argument')
		return EFAULT
	}

	# If the path is empty and AT_EMPTY_PATH is set, the system call behaves like fstat
	if has_flag(flags, AT_EMPTY_PATH) and path.length == 0 return system_fstat(directory_descriptor, buffer)

	# Output path as debugging information
	debug.write('System call: Fstatat: Path = ') debug.write_line(path)

	local_allocator = LocalHeapAllocator()

	# Figure out the custody of the specified directory, so that we can look for the file
	custody_or_error = load_custody(allocator, process, directory_descriptor, path)

	if custody_or_error.has_error {
		local_allocator.deallocate()
		return custody_or_error.error
	}

	custody = custody_or_error.get_value()

	# Lookup the file status into the user buffer
	result = FileSystems.root.lookup_status(custody, path, buffer as FileMetadata)
	
	local_allocator.deallocate()
	return result
}

# System call: fstatat
export system_statx(directory_descriptor: u32, path_argument: link, flags: u32, mask: u32, buffer: link): u32 {
	debug.write('System call: statx: ')
	debug.write('directory_descriptor=') debug.write(directory_descriptor)
	debug.write(', path=') debug.write_address(path_argument)
	debug.write(', flags=') debug.write(flags)
	debug.write(', mask=') debug.write(mask)
	debug.write(', buffer=') debug.write_address(buffer)
	debug.write_line()

	process = get_process()
	allocator = BufferAllocator(allocator_buffer: u8[PATH_MAX], PATH_MAX)

	# Load the path argument into a string
	if load_string(allocator, process, path_argument, PATH_MAX) has not path {
		debug.write_line('System call: statx: Invalid path argument')
		return EFAULT
	}

	# Output path as debugging information
	debug.write('System call: statx: Path = ') debug.write_line(path)

	local_allocator = LocalHeapAllocator()

	# Figure out the custody of the specified directory, so that we can look for the file
	custody_or_error = load_custody(allocator, process, directory_descriptor, path)

	if custody_or_error.has_error {
		local_allocator.deallocate()
		return custody_or_error.error
	}

	custody = custody_or_error.get_value()

	# Lookup the file status
	result = FileSystems.root.lookup_extended_status(custody, path, buffer as FileMetadataExtended)
	buffer.(FileMetadataExtended).mask = mask

	local_allocator.deallocate()
	return result
}