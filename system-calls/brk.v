namespace kernel.system_calls

# Summary call: brk
export system_brk(new_break: u64) {
	debug.write('System call: Break: ')
	debug.write('break=') debug.write_address(new_break)
	debug.write_line()

	# Ensure the break address is allowed
	process = get_process()
	old_break = process.memory.state.break

	if new_break == 0 or new_break > process.memory.state.max_break {
		debug.write('System call: Break: Returning the current break ')
		debug.write_address(old_break)
		debug.write_line()
		return old_break 
	}

	# If the break increases, we must allocate the region between the new and the old break
	region = Segment.new(math.min(old_break, new_break), math.max(old_break, new_break))

	if new_break > old_break {
		process.memory.allocate_specific_region(ProcessMemoryRegion.new(region))
	} else {
		process.memory.deallocate(region)
	}

	# Update the break address
	process.memory.state.break = new_break
	return new_break 
}