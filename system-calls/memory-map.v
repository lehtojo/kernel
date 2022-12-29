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
	# TODO: Access the current process through the scheduler and use its memory manager
	process = interrupts.scheduler.current
	require(process !== none, 'Missing process')

	# TODO: Support alignment
	result = process.memory.allocate_region_anywhere(length, PAGE_SIZE)
	if result has not mapping return SYSTEM_CALL_ERROR_NO_MEMORY

	# Map the pages for the process
	process.memory.paging_table.map_region(HeapAllocator.instance, mapping)

	# Return the virtual starting address of the allocated region
	return mapping.virtual_address_start
}