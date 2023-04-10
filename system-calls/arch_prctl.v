namespace kernel.system_calls

# System call: arch_prctl
export system_arch_prctl(code: u32, address: u64): u64 {
	debug.write('System call: Set architecture-specific thread state: ')
	debug.write('code=') debug.write(code)
	debug.write(', address=') debug.write_address(address)
	debug.write_line()

	if code == ARCH_SET_FS {
		# Todo: Implement
		return 0
	} else code == ARCH_GET_FS {
		# Todo: Implement
	}

	return EINVAL
}