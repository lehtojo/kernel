namespace kernel.system_calls

# Summary: pread64
export system_pread64(file_descriptor: u32, buffer: link, size: u64, position: u64) {
	debug.write('System call: Positional read (pread): ')
	debug.write('file_descriptor=') debug.write(file_descriptor)
	debug.write(', buffer=') debug.write_address(buffer)
	debug.write(', size=') debug.write(size)
	debug.write(', position=') debug.write(position)
	debug.write_line()

	process = get_process()

	# Verify the specified buffer is valid
	if not is_valid_region(process, buffer, size) {
		debug.write_line('System call: Positional read (pread): Invalid memory region')
		return EFAULT
	}

	# Try getting the file description associated with the specified descriptor
	file_description = process.file_descriptors.try_get_description(file_descriptor)

	if file_description === none {
		debug.write_line('System call: Positional read (pread): Invalid file descriptor')
		return EBADF
	}

	# Ensure the file is seekable
	if not file_description.can_seek() return EINVAL 

	return file_description.read(buffer, position, size)
}