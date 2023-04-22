namespace kernel.system_calls

# System call: getgid
export system_getgid(): u32 {
	debug.write_line('System call: getgid')
	return get_process().credentials.gid
}