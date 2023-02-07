namespace kernel.system_calls

import kernel.file_systems

# System call: close
export system_close(file_descriptor: u32): i32 {
	debug.write('System call: Close: ')
	debug.write('file_descriptor=') debug.write(file_descriptor)
	debug.write_line()

	# Todo: Implement
	return 0
}