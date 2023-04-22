namespace kernel.system_calls

# System call: rt_sigaction
export system_rt_sigaction(signal: i32, new_action: link, old_action: link): i32 {
	debug.write('System call: rt_sigaction: ')
	debug.write('new_action=') debug.write_address(new_action)
	debug.write('old_action=') debug.write_address(old_action)
	debug.write_line()

	# Todo: Implement
	return 0
}