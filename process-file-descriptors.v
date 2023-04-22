namespace kernel.scheduler

import kernel.system_calls
import kernel.file_systems

pack FileDescriptorState {
	allocated: bool
	description: OpenFileDescription

	shared new(): FileDescriptorState {
		return pack { allocated: false, description: none as OpenFileDescription } as FileDescriptorState
	}
}

plain ProcessFileDescriptors {
	private allocator: Allocator
	private descriptors: List<FileDescriptorState>
	private max_descriptors: u32

	init(allocator: Allocator, max_descriptors: u32) {
		this.allocator = allocator
		this.descriptors = List<FileDescriptorState>(allocator) using allocator
		this.max_descriptors = max_descriptors
	}

	# Summary: Attempts to allocate a file descriptor (>= min) for usage
	allocate(min: u32): Optional<u32> {
		# Look for a file descriptor that is no longer allocated
		loop (i = min, i < descriptors.size, i++) {
			if not descriptors[i].allocated return Optionals.new<i64>(i)
		}

		# Do not exceed the maximum number of descriptors
		if descriptors.size >= max_descriptors or min >= max_descriptors {
			return Optionals.empty<u32>()
		}

		# Ensure there are at least "min" number of descriptors
		loop (i = descriptors.size, i < min, i++) {
			descriptors.add(FileDescriptorState.new())
		}

		# Allocate a new file descriptor
		descriptors.add(FileDescriptorState.new())

		return descriptors.size - 1
	}

	# Summary: Attempts to allocate a file descriptor for usage
	allocate(): Optional<u32> {
		return allocate(0)
	}

	# Summary: Attempts to attach the specified file description to the specified file descriptor
	attach(descriptor: u32, description: OpenFileDescription): bool {
		require(descriptors.bounds.inside(descriptor), 'File descriptor out of bounds')

		# Load the descriptor and ensure it is not allocated
		state = descriptors[descriptor]
		if state.allocated return false

		state.allocated = true
		state.description = description
		descriptors[descriptor] = state
		return true
	}

	# Summary:
	# Returns the file description attached to the specified file descriptor, 
	# if it exists and is open. Otherwise, none is returned.
	try_get_description(file_descriptor: u32): OpenFileDescription {
		# Ensure the file descriptor exists
		if file_descriptor >= descriptors.size return none as OpenFileDescription

		# Require the descriptor to be allocated
		descriptor = descriptors[file_descriptor]
		if not descriptor.allocated return none as OpenFileDescription

		return descriptor.description
	}

	# Summary: Attempts to duplicate the specified file descriptor
	duplicate(file_descriptor: u32, min: u32): i32 {
		# Output debug information
		debug.write('Process file descriptors: Duplicating file descriptor ')
		debug.write_line(file_descriptor)

		# Find the description associated with the descriptor
		file_description = try_get_description(file_descriptor)
		if file_description === none return EBADF

		# Attempt to allocate a new descriptor (> min)
		if allocate(min) has not duplicated_file_descriptor return EINVAL

		# Attach the description to the new descriptor
		if not attach(duplicated_file_descriptor, file_description) return EINVAL

		debug.write('Process file descriptors: Successfully duplicated the file descriptor (')
		debug.write(duplicated_file_descriptor)
		debug.write_line(')')

		# Return the duplicated descriptor
		return duplicated_file_descriptor
	}

	# Summary: Attempts to close the specified file descriptor
	close(file_descriptor: u32): u32 {
		# Ensure the file descriptor exists
		if file_descriptor >= descriptors.size {
			debug.write_line('Process file descriptors: Failed to close, because the file descriptor did not exist')
			return EBADF
		}

		# Require the descriptor to be allocated before closing
		state = descriptors[file_descriptor]

		if not state.allocated {
			debug.write_line('Process file descriptors: Failed to close, because the file descriptor was not allocated')
			return EBADF
		}

		debug.write_line('Process file descriptors: Deallocating the file descriptor and closing its description')

		# Set the descriptor deallocated and empty
		descriptors[file_descriptor] = FileDescriptorState.new()

		# Close the file description and return potential errors from there
		return state.description.close()
	}

	destruct() {
		descriptors.destruct(allocator)
		allocator.deallocate(this as link)
	}
}