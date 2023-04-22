namespace kernel.system_calls

# System call: getrandom
export system_getrandom(buffer: link, size: u64, flags: u32): u64 {
	debug.write('System call: getrandom: ')
	debug.write('buffer=') debug.write_address(buffer)
	debug.write(', size=') debug.write(size)
	debug.write(', flags=') debug.write(flags)
	debug.write_line()

	# Verify the specified buffer is valid
	if not is_valid_region(get_process(), buffer, size, true) {
		debug.write_line('System call: getrandom: Invalid buffer')
		return EFAULT
	}

	# Todo: Implement
	loop (i = 0, i < size, i++) {
		buffer[i] = 42
	}

	return size
}