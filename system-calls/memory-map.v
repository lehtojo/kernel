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
}