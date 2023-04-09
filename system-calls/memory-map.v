namespace kernel.system_calls

constant MAP_ANONYMOUS = 0x20

# Summary: Creates process memory options based on the specified data
create_process_memory_region_options(process: Process, flags: u32, file_descriptor: u32, offset: u64): Result<ProcessMemoryRegionOptions, u32> {
	options = ProcessMemoryRegionOptions.new()
	options.offset = offset

	if not has_flag(flags, MAP_ANONYMOUS) {
		# Attempt to get the file description based on the specified file descriptor
		description = process.file_descriptors.try_get_description(file_descriptor)

		if description === none {
			debug.write_line('System call: Memory map: Invalid file descriptor')
			return Results.error<ProcessMemoryRegionOptions, u32>(EBADF)
		}

		# Todo: Do some checks on the file description
		if not description.file.is_inode() {
			debug.write_line('System call: Memory map: File descriptor does not refer to an inode')
			return Results.error<ProcessMemoryRegionOptions, u32>(EBADF)
		} 

		# Store the inode in the options
		inode = description.file.(InodeFile).inode
		options.inode = Optionals.new<Inode>(inode)

		# Output debug information
		debug.write('System call: Memory map: Attaching inode to memory region: ')
		inode.identifier.print()
		debug.write_line()
	}

	debug.write_line('System call: Memory map: Creating memory region options')
	return Results.new<ProcessMemoryRegionOptions, u32>(options)
}

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
	options_result = create_process_memory_region_options(process, flags, file_descriptor, offset)
	if not options_result.has_value return options_result.error

	options = options_result.value

	if address == 0 {
		result = process.memory.allocate_region_anywhere(options, length, PAGE_SIZE)
	} else process.memory.allocate_specific_region(ProcessMemoryRegion.new(Segment.new(address, address + length), options)) {
		result = Optionals.new<u64>(address as u64)
	} else {
		# If the specific allocation failed, attempt to allocate anywhere
		result = process.memory.allocate_region_anywhere(options, length, PAGE_SIZE)
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