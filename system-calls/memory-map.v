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
	result = Optionals.empty<MemoryMapping>()

	if address == 0 {
		result = process.memory.allocate_region_anywhere(length, PAGE_SIZE)
	} else {
		result = process.memory.allocate_specific_region(address as u64, length)

		# If the specific allocation failed, attempt to allocate anywhere
		if result.empty { result = process.memory.allocate_region_anywhere(length, PAGE_SIZE) }
	}

	if result has not mapping {
		debug.write_line('System call: Memory map: Failed to find a memory region for the process')
		return ENOMEM
	}

	debug.write('System call: Memory map: Found memory region for the process ')
	debug.write_address(mapping.virtual_address_start)
	debug.write(' => ')
	debug.write_address(mapping.physical_address_start)
	debug.write(' ')
	debug.write(mapping.size)
	debug.write_line(' bytes')

	# Map the pages for the process
	process.memory.paging_table.map_region(HeapAllocator.instance, mapping)

	# Return the virtual starting address of the allocated region
	return mapping.virtual_address_start
}