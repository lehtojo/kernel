namespace kernel.system_calls

# Summary: getdents64
export system_getdents64(file_descriptor: u32, output_entries: link, output_entries_size: u64): u64 {
	debug.write('System call: Get directory entries: ')
	debug.write('file_descriptor=') debug.write(file_descriptor)
	debug.write(', output_entries=') debug.write_address(output_entries)
	debug.write(', output_entries_size=') debug.write(output_entries_size)
	debug.write_line()

	process = get_process()

	# Validate the output entry list region
	if not is_valid_region(process, output_entries, output_entries_size, true) {
		debug.write_line('System call: Get directory entries: Invalid entry list')
		return EFAULT
	}
 
	# Try getting the file description associated with the specified descriptor
	file_description = process.file_descriptors.try_get_description(file_descriptor)

	if file_description === none {
		debug.write_line('System call: Get directory entries: Invalid file descriptor')
		return EBADF
	}

	# Verify the loaded file description represents a directory
	if not file_description.is_directory {
		debug.write_line('System call: Get directory entries: Specified file descriptor did not represent a directory')
		return ENOTDIR
	}

	return file_description.get_directory_entries(MemoryRegion(output_entries, output_entries_size))
}