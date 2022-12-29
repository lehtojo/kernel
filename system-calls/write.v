namespace kernel.system_calls

# System call: write
export system_write(file_descriptor: u32, buffer: link, count: u64) {
	process = interrupts.scheduler.current
	require(process !== none, 'Missing process')

	# Map the user virtual address into physical address that the kernel can use
	if process.memory.paging_table.to_physical_address(buffer) has not physical_address return

	debug.write_bytes(physical_address, count)
}