namespace kernel.system_calls

# System call: mmap
export system_memory_map(
	address: link,
	length: u64,
	protection: u32,
	flags: u32,
	file_descriptor: u32,
	offset: u64
): link {
	debug.write('System call: Memory map: ')
	debug.write('address=') debug.write_address(address)
	debug.write(', length=') debug.write(length)
	debug.write(', protection=') debug.write(protection)
	debug.write(', flags=') debug.write(flags)
	debug.write(', file_descriptor=') debug.write(file_descriptor)
	debug.write(', offset=') debug.write(offset)
	debug.write_line()

	process = get_process()

	# Use multiple of pages when allocating
	length = memory.round_to_page(length) # Todo: Overflow

	# We are allowed to align the specified address to pages as it is only a hint and other implementations do this as well
	address = memory.round_to_page(address) # Todo: Overflow

	# If the specified address is zero, allocate a suitable region anywhere.
	# Otherwise try to allocate the specified region.
	result = Optionals.empty<u64>()

	# Todo: Support MAP_FIXED that forces the specified address and updates its settings

	if address == 0 {
		result = process.memory.allocate_region_anywhere(length, PAGE_SIZE)
	} else process.memory.allocate_specific_region(address as u64, length) {
		result = Optionals.new<u64>(address as u64)
	} else {
		# If the specific allocation failed, attempt to allocate anywhere
		result = process.memory.allocate_region_anywhere(length, PAGE_SIZE)
	}

	# Return the allocated virtual address
	if result has virtual_address {
		debug.write('System call: Memory map: Found virtual region for process ')
		debug.write_address(virtual_address)
		debug.write_line()
		return virtual_address
	}

	debug.write_line('System call: Memory map: Failed to find a memory region for the process')
	return ENOMEM
}