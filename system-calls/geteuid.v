
namespace kernel.system_calls

# System call: geteuid 
export system_geteuid(): u32 {
	debug.write_line('System call: geteuid')
	return get_process().credentials.euid
}