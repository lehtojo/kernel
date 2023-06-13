namespace kernel.system_calls

# System call: statfs
export system_statfs(path: link, buffer: link): u64 {
	debug.write('System call: statfs: ')
	debug.write('path=') debug.write_address(path)
	debug.write(', buffer=') debug.write_address(buffer)
	debug.write_line()

	# Todo: Implement
	return ENOENT
}