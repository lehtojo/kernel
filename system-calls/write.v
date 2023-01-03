namespace kernel.system_calls

# System call: write
export system_write(file_descriptor: u32, buffer: link, count: u64) {
	process = interrupts.scheduler.current
	require(process !== none, 'Missing process')

	debug.write_bytes(buffer, count)
}