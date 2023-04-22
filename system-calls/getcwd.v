namespace kernel.system_calls

# System call: getcwd
export system_getcwd(buffer: link, size: u64): i32 {
	debug.write('System call: getcwd: ')
	debug.write('buffer=') debug.write_address(buffer)
	debug.write(', size=') debug.write(size)
	debug.write_line()

	process = get_process()

	# Verify the specified buffer is valid
	if not is_valid_region(process, buffer, size, true) {
		debug.write('System call: getcwd: Invalid buffer')
		return EFAULT
	}

	# Load the current working directory
	working_directory = process.working_directory

	# Verify the working directory fits in the specified buffer including the zero terminator
	if working_directory.length >= size {
		debug.write('System call: getcwd: Buffer is not large enough')
		return ERANGE
	}

	# Copy the working directory string into the buffer including the null terminator
	memory.copy(buffer, working_directory.data, working_directory.length + 1)
	return buffer
}