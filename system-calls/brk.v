namespace kernel.system_calls

# Summary call: brk
export system_brk(address: link) {
	debug.write('System call: Break: ')
	debug.write('address=') debug.write_address(address)
	debug.write_line()

	# Todo: Implement this system call
	# Todo: Continue investigation in _dl_sysdep_start

	return ENOMEM
}