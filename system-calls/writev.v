namespace kernel.system_calls

constant MAX_VECTORS = 256 # Todo: Use the real value

pack IoVector {
	start: link
	size: u64
}

# System call: writev
export system_writev(file_descriptor: u32, argument_vectors: link, vector_count: u64) {
	vectors = argument_vectors as IoVector*

	debug.write('System call: Write vector: ')
	debug.write('file_descriptor=') debug.write(file_descriptor)
	debug.write(', vectors=') debug.write_address(vectors)
	debug.write(', vector_count=') debug.write(vector_count)
	debug.write_line()

	process = get_process()

	# Verify the user has not passed too many vectors
	if vector_count > MAX_VECTORS return EINVAL

	# Verify the vector list is valid
	if not is_valid_region(process, vectors, vector_count * sizeof(IoVector)) {
		debug.write_line('System call: Write vector: Invalid vector list')
		return EINVAL
	}

	# Todo: You should copy the vectors before checking them, because 
	# the vectors could change in between and they are reloaded after this loop
	# Todo: Verify the number of bytes does not overflow
	# Todo: Should the system call fail, if all the vectors can not be written completely?

	# Verify each vector is valid
	loop (i = 0, i < vector_count, i++) {
		vector = vectors[i]

		if not is_valid_region(process, vector.start, vector.size) {
			debug.write_line('System call: Write vector: Invalid vector')
			return EINVAL
		}
	}

	# Try getting the file description associated with the specified descriptor
	file_description = process.file_descriptors.try_get_description(file_descriptor)

	if file_description === none {
		debug.write_line('System call: Write vector: Invalid file descriptor')
		return EBADF
	}

	# Store the number of bytes written out
	written: u64 = 0

	# Write out the vectors
	loop (i = 0, i < vector_count, i++) {
		vector = vectors[i]
		debug.write('System call: Write vector: Writing ')
		debug.write(vector.size)
		debug.write(' byte(s) from address ')
		debug.write_address(vector.start)
		debug.write_line()

		# Todo: Remove
		debug.write_bytes(vector.start, vector.size)
		debug.write_line()

		result = file_description.write(Array<u8>(vector.start, vector.size))

		# Stop and return the error if we encountered one
		if is_error_code(result) return result

		written += result
	}

	return written
}