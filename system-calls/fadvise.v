namespace kernel.system_calls

# System call: fadvise
export system_fadvice(file_descriptor: u32, offset: u64, length: u64, advice: u32): u64 {
	debug.write('System call: fadvise: ')
	debug.write('file_descriptor=') debug.write(file_descriptor)
	debug.write(', offset=') debug.write(offset)
	debug.write(', length=') debug.write(length)
	debug.write(', advice=') debug.write(advice)
	debug.write_line()

	# Todo: Do something?
	return 0
}