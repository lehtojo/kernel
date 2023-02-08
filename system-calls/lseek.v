namespace kernel.system_calls

constant SEEK_SET = 0
constant SEEK_CUR = 1
constant SEEK_END = 2

export system_seek(file_descriptor: u32, offset: i64, whence: i32): u64 {
	debug.write('System call: Seek: ')
	debug.write('file_descriptor=') debug.write(file_descriptor)
	debug.write(', offset=') debug.write(offset)
	debug.write(', whence=') debug.write(whence)
	debug.write_line()

	process = get_process()

	# Validate argument whence
	if whence != SEEK_SET and whence != SEEK_CUR and whence != SEEK_END {
		debug.write_line('System call: Seek: Invalid argument whence')
		return EINVAL
	}

	# Try getting the file description associated with the specified descriptor
	file_description = process.file_descriptors.try_get_description(file_descriptor)

	if file_description === none {
		debug.write_line('System call: Seek: Invalid file descriptor')
		return EBADF
	}

	return file_description.seek(offset, whence)
}