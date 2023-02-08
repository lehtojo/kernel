namespace kernel.system_calls

# System call: Read
export system_read(file_descriptor: u32, buffer: link, size: u64): u64 {
	debug.write('System call: Read: ')
	debug.write('file_descriptor=') debug.write(file_descriptor)
	debug.write(', buffer=') debug.write_address(buffer)
	debug.write(', size=') debug.write(size)
	debug.write_line()

	process = get_process()

	# Verify the specified buffer is valid
	if not is_valid_region(process, buffer, size) {
		debug.write_line('System call: Read: Invalid memory region')
		return EFAULT
	}

	# Try getting the file description associated with the specified descriptor
	file_description = process.file_descriptors.try_get_description(file_descriptor)

	if file_description === none {
		debug.write_line('System call: Read: Invalid file descriptor')
		return EBADF
	}

	return file_description.read(buffer, size)
}