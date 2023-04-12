namespace kernel.system_calls

# System call: set_robust_list
export system_set_robust_list(robust_list_head: link, length: u64): u64 {
	debug.write('System call: Set robust list: ')
	debug.write('robust_list_head=') debug.write_address(robust_list_head)
	debug.write(', length=') debug.write(length)
	debug.write_line()

	# Todo: Implement

	return 0
}