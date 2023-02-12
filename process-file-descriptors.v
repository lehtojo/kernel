namespace kernel.scheduler

import kernel.file_systems

pack FileDescriptorState {
	allocated: bool
	description: kernel.file_systems.OpenFileDescription # Todo: Remove full path

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

	# Summary: Attempts to allocate a file descriptor for usage
	allocate(): Optional<u32> {
		# Look for a file descriptor that is no longer allocated
		loop (i = 0, i < descriptors.size, i++) {
			if not descriptors[i].allocated return Optionals.new<i64>(i)
		}

		# Do not exceed the maximum number of descriptors
		if descriptors.size >= max_descriptors return Optionals.empty<u32>()

		# Allocate a new file descriptor
		descriptors.add(FileDescriptorState.new())

		return descriptors.size - 1
	}

	# Summary: Attempts to attach the specified file description to the specified file descriptor
	attach(descriptor: u32, description: kernel.file_systems.OpenFileDescription): bool {
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
	try_get_description(file_descriptor: u32): kernel.file_systems.OpenFileDescription {
		# Ensure the file descriptor exists
		if file_descriptor >= descriptors.size return none as OpenFileDescription

		# Require the descriptor to be allocated
		descriptor = descriptors[file_descriptor]
		if not descriptor.allocated return none as OpenFileDescription

		return descriptor.description
	}

	# Summary: Attempts to close the specified file descriptor
	close(file_descriptor: u32): u32 {
		# Ensure the file descriptor exists
		if file_descriptor >= descriptors.size {
			debug.write_line('Process file descriptors: Failed to close, because the file descriptor did not exist')
			return kernel.system_calls.EBADF
		}

		# Require the descriptor to be allocated before closing
		state = descriptors[file_descriptor]

		if not state.allocated {
			debug.write_line('Process file descriptors: Failed to close, because the file descriptor was not allocated')
			return kernel.system_calls.EBADF
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