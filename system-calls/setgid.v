namespace kernel.system_calls

# System call: setpgrp
export system_setpgrp(pid: u32, gid: u32): i32 {
	debug.write('System call: setpgrp: ')
	debug.write('pid=') debug.write(pid)
	debug.write(', gid=') debug.write(gid)
	debug.write_line()

	# Load the calling process as default
	process_or_empty = Optionals.new<Process>(get_process())

	# Find a process by pid, if the specified pid is not zero
	if pid != 0 { process_or_empty = interrupts.scheduler.find(pid) }

	if process_or_empty has not process {
		debug.write_line('System call: setpgrp: Failed to find the process')
		return ESRCH
	}

	# Update the process gid
	# Todo: Add restrictions
	process.credentials.gid = gid
	return 0
}