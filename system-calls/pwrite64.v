namespace kernel.system_calls

# Summary: pwrite64
export system_pwrite64(file_descriptor: u32, buffer: link, size: u64, position: u64) {
	debug.write('System call: Positional write (pwrite): ')
	debug.write('file_descriptor=') debug.write(file_descriptor)
	debug.write(', buffer=') debug.write_address(buffer)
	debug.write(', size=') debug.write(size)
	debug.write(', position=') debug.write(position)
	debug.write_line()

	process = get_process()

	# Verify the specified buffer is valid
	if not is_valid_region(process, buffer, size, false) {
		debug.write_line('System call: Positional write (pwrite): Invalid memory region')
		return EFAULT
	}

	# Try getting the file description associated with the specified descriptor
	file_description = process.file_descriptors.try_get_description(file_descriptor)

	if file_description === none {
		debug.write_line('System call: Positional write (pwrite): Invalid file descriptor')
		return EBADF
	}

	# Ensure the file is seekable
	if not file_description.can_seek() return EINVAL 

	return file_description.write(Array<u8>(buffer, size), position)
}