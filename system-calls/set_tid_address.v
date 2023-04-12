namespace kernel.system_calls

# System call: set_tid_address
export system_set_tid_address(tid: u64): u64 {
	debug.write('System call: Set TID address: ')
	debug.write('tid=') debug.write_address(tid)
	debug.write_line()

	# Todo: Implement

	return 0
}