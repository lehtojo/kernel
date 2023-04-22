namespace kernel.system_calls

# System call: getgid
export system_getgid(): u32 {
	debug.write_line('System call: getgid')
	return get_process().credentials.gid
}

# System call: getpgrp
export system_getpgrp(): u32 {
	debug.write_line('System call: getpgrp')
	return get_process().credentials.gid
}