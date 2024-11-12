
namespace kernel.system_calls

# System call: getppid
export system_getppid(): u32 {
	debug.write_line('System call: getppid')
	process = get_process()

	if process.parent === none return 0
	return process.parent.pid
}