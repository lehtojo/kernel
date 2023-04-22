namespace kernel.system_calls

# System call: fcntl
export system_fcntl(file_descriptor: u32, command: u32, argument: u64): i32 {
	debug.write('System call: fcntl: ')
	debug.write('file_descriptor=') debug.write(file_descriptor)
	debug.write(', command=') debug.write(command)
	debug.write(', argument=') debug.write(argument)
	debug.write_line()

	process = get_process()

	return when (command) {
		F_DUPFD => process.file_descriptors.duplicate(file_descriptor, argument),
		else => EINVAL
	}
}