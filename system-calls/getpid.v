namespace kernel.system_calls

# System call: getpid
export system_getpid(): u64 {
	return get_process().pid
}