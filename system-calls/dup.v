namespace kernel.system_calls

# System call: dup2
export system_dup2(old_descriptor: u32, new_descriptor: u32): u64 {
	debug.write('System call: dup2: ')
	debug.write('old_descriptor=') debug.write(old_descriptor)
	debug.write(', new_descriptor=') debug.write(new_descriptor)
	debug.write_line()

	process = get_process()

	# Attempt to find the old file descriptor
	old_description = process.file_descriptors.try_get_description(old_descriptor)
	if old_description === none return EBADF

	# If the old and new descriptors are the same, do nothing
	if old_descriptor == new_descriptor return new_descriptor

	# If the new descriptor is already in use, close it silently.
	# Specification: "the close is performed silently (i.e., any errors during the close are not reported by dup2())"
	process.file_descriptors.close(new_descriptor)

	# Allocate the new file descriptor
	require(process.file_descriptors.allocate(new_descriptor) has allocated_descriptor and allocated_descriptor == new_descriptor, 'Failed to allocate the new file descriptor')
	require(process.file_descriptors.attach(new_descriptor, old_description), 'Failed to attach the new file descriptor')

	return 0
}