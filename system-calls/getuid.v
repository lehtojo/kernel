
namespace kernel.system_calls

# System call: getuid
export system_getuid(): u32 {
	debug.write_line('System call: getuid')
	return get_process().credentials.uid
}