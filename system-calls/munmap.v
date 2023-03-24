namespace kernel.system_calls

# System call: munmap
export system_munmap(address: link, length: u64): i64 {
	debug.write('System call: Memory unmap (munmap): ')
	debug.write('address=') debug.write_address(address)
	debug.write(', length=') debug.write(length)
	debug.write_line()

	process = get_process()

	# Use multiple of pages when allocating
	length = memory.round_to_page(length) # Todo: Overflow

	return process.memory.deallocate(Segment.new(address, address + length)) # Todo: Overflow
}