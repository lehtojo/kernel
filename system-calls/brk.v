namespace kernel.system_calls

# Summary call: brk
export system_brk(break: u64) {
	debug.write('System call: Break: ')
	debug.write('break=') debug.write_address(break)
	debug.write_line()

	# Ensure the break address is allowed
	process = get_process()

	if break == 0 or break > process.memory.max_break {
		debug.write('System call: Break: Returning the current break ')
		debug.write_address(process.memory.break)
		debug.write_line()
		return process.memory.break
	}

	# Update the break address
	process.memory.break = break
	return break
}