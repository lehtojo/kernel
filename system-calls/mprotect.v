namespace kernel.system_calls

# System call: mprotect 
export system_mprotect(start: u64, size: u64, protection: u64): u64 {
	debug.write('System call: Mprotect: ')
	debug.write('start=') debug.write_address(start)
	debug.write(', size=') debug.write(size)
	debug.write(', protection=') debug.write(protection)
	debug.write_line()

	# Todo: Implement

	return 0
}