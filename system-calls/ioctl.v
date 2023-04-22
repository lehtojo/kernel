namespace kernel.system_calls

# System call: ioctl
export system_ioctl(file_descriptor: u32, request: u32, argument: u64): i32 {
	debug.write('System call: ioctl: ')
	debug.write('file_descriptor=') debug.write(file_descriptor)
	debug.write(', request=') debug.write(request)
	debug.write(', argument=') debug.write_address(argument)
	debug.write_line()

	process = get_process()

	# Try getting the file description associated with the specified descriptor
	file_description = process.file_descriptors.try_get_description(file_descriptor)

	if file_description === none {
		debug.write_line('System call: ioctl: Invalid file descriptor')
		return EBADF
	}

	# Verify the file descriptor represents a device
	if not file_description.file.is_device() {
		debug.write_line('System call: ioctl: File descriptor did not represent a device')
		return ENOTTY
	}

	return file_description.file.(Device).control(request, argument)
}