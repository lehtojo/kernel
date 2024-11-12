namespace kernel.system_calls

# System call: gettid
export system_gettid(): i64 {
	debug.write_line('System call: gettid')
	return get_process().tid
}