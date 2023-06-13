namespace kernel.system_calls

# System call: arch_prctl
export system_arch_prctl(code: u32, address: u64): u64 {
	debug.write('System call: Set architecture-specific thread state: ')
	debug.write('code=') debug.write(code)
	debug.write(', address=') debug.write_address(address)
	debug.write_line()

	process = get_process()

	if code == ARCH_SET_FS {
		debug.write_line('System call: Set architecture-specific thread state: Setting the value of register fs')
		enable_general_purpose_segment_instructions()
		write_fs_base(address)
		process.fs = address
		disable_general_purpose_segment_instructions()
		return 0
	} else code == ARCH_GET_FS {
		debug.write_line('System call: Set architecture-specific thread state: Loading the value of register fs')
		enable_general_purpose_segment_instructions()
		result = read_fs_base()
		disable_general_purpose_segment_instructions()
		return result
	}

	return EINVAL
}