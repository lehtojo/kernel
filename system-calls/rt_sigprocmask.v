namespace kernel.system_calls

# System call: rt_sigprocmask
export system_rt_sigprocmask(how: i32, set: link, old_set: link, size: u64): i32 {
	debug.write('System call: rt_sigprocmask ')
	debug.write('how=') debug.write(how)
	debug.write(', set=') debug.write_address(set)
	debug.write(', old_set=') debug.write_address(old_set)
	debug.write(', size=') debug.write(size)
	debug.write_line()

	# Todo: Implement
	return 0
}