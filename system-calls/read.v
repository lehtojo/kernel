namespace kernel.system_calls

# Summary: Attempts to read data from the specified description while considering blocking
read_from_description(process: Process, description: OpenFileDescription, buffer: link, size: u64): i64 {
	# Attempt to read data from the description
	result = description.read(buffer, size)

	# If there is no data available and the description is blocking, block the current thread
	if result == 0 and description.is_blocking {
		blocker = FileBlocker.try_create(HeapAllocator.instance, description, buffer, size)
		if blocker === none return EIO # Todo: Correct error code

		process.block(blocker.then((blocker: FileBlocker) -> {
			result = blocker.description.read(blocker.buffer, blocker.size)
			if result == 0 return false

			blocker.set_system_call_result(result)
			return true
		}))
	}

	return result
}

# System call: Read
export system_read(file_descriptor: u32, buffer: link, size: u64): u64 {
	debug.write('System call: Read: ')
	debug.write('file_descriptor=') debug.write(file_descriptor)
	debug.write(', buffer=') debug.write_address(buffer)
	debug.write(', size=') debug.write(size)
	debug.write_line()

	process = get_process()

	# Verify the specified buffer is valid
	if not is_valid_region(process, buffer, size, true) {
		debug.write_line('System call: Read: Invalid memory region')
		return EFAULT
	}

	# Try getting the file description associated with the specified descriptor
	file_description = process.file_descriptors.try_get_description(file_descriptor)

	if file_description === none {
		debug.write_line('System call: Read: Invalid file descriptor')
		return EBADF
	}

	return read_from_description(process, file_description, buffer, size)
}