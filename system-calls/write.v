namespace kernel.system_calls

# System call: write
export system_write(file_descriptor: u32, buffer: link, size: u64): u64 {
	process = get_process()

	# Verify the specified buffer is valid
	if not is_valid_region(buffer, size) return EFAULT

	# Todo: Remove
	debug.write_bytes(buffer, size)

	# Try getting the file description associated with the specified descriptor
	file_description = process.file_descriptors.try_get_description(file_descriptor)
	if file_description === none return EBADF

	return file_description.write(buffer, size)
}