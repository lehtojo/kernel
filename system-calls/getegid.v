
namespace kernel.system_calls

# System call: getegid
export system_getegid(): u32 {
	debug.write_line('System call: getegid')
	return get_process().credentials.egid
}