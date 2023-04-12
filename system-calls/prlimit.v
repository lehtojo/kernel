namespace kernel.system_calls

# System call: prlimit 
export system_prlimit(pid: u64, resource: u64, new_limit: link, old_limit: link): u64 {
	debug.write('System call: Prlimit: ')
	debug.write('pid=') debug.write(pid)
	debug.write(', resource=') debug.write(resource)
	debug.write(', new_limit=') debug.write_address(new_limit)
	debug.write(', old_limit=') debug.write_address(old_limit)
	debug.write_line()

	# Todo: Implement

	return 0
}