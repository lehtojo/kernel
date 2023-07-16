namespace kernel.file_systems.ext2

Action<u64> ProgressTracker {
	# Summary: Stores the process that will be unblocked on completion
	process: Process
	# Summary: Stores the current progress
	progress: u64 = 0
	# Summary: Stores the progress that will trigger a completion
	end: u64
	# Summary: Stores the status of all operations
	status: u64 = 0

	init(process: Process, end: u64) {
		this.process = process
		this.end = end
	}

	override execute(status: u64) {
		# Store error status if we get one
		if status != 0 { this.status = status }

		if ++progress < end return

		process.unblock()
	}
} 

Inode Ext2Inode {
	allocator: Allocator
	name: String
	blocks: List<u32> = none as List<u32> 
	inline information: InodeInformation

	block_size => file_system.(Ext2).block_size

	init(allocator: Allocator, file_system: FileSystem, index: u64, name: String) {
		Inode.init(file_system, index)

		this.allocator = allocator
		this.name = name
	}

	private process_block_entries(block: u32, remaining: i64, processor: (Ext2Inode, u32, i64) -> i64): i64 {		
		entries = KernelHeap.allocate(block_size) as u32*
		if entries === none return ENOMEM

		result = file_system.(Ext2).read_block(entries as u64, block, 0, block_size)

		if result != 0 {
			KernelHeap.deallocate(entries)
			return result
		}

		entries_in_block = block_size / sizeof(u32)

		loop (i = 0, i < entries_in_block and remaining > 0, i++) {
			remaining = processor(this, entries[i], remaining)
		}

		KernelHeap.deallocate(entries)
		return remaining
	}

	private load_block_list(): i64 {
		if blocks !== none {
			debug.write_line('Ext2 inode: Block list is already loaded')
			return 0
		}

		debug.write_line('Ext2 inode: Loading block list...')

		remaining = (information.size + block_size - 1) / block_size
		debug.write('Ext2 inode: Expecting ') debug.write(remaining) debug.write_line(' block(s)')

		blocks = List<u32>(allocator, remaining, false) using allocator

		loop (i = 0, i < BLOCK_POINTER_COUNT and remaining > 0, i++) {
			blocks.add(information.block_pointers[i])
			remaining--
		}

		if remaining <= 0 {
			debug.write('Ext2 inode: Finished reading block list with status ') debug.write_line(remaining)
			return remaining
		}

		remaining = process_block_entries(information.singly_indirect_block_pointer, remaining, (inode: Ext2Inode, block: u32, remaining: u32) -> {
			inode.blocks.add(block)
			return remaining - 1
		})

		if remaining <= 0 {
			debug.write('Ext2 inode: Finished reading block list with status ') debug.write_line(remaining)
			return remaining
		}

		remaining = process_block_entries(information.doubly_indirect_block_pointer, remaining, (inode: Ext2Inode, block: u32, remaining: u32) -> {
			return inode.process_block_entries(block, remaining, (inode: Ext2Inode, block: u32, remaining: u32) -> {
				inode.blocks.add(block)
				return remaining - 1
			})
		})

		if remaining <= 0 {
			debug.write('Ext2 inode: Finished reading block list with status ') debug.write_line(remaining)
			return remaining
		}

		remaining = process_block_entries(information.triply_indirect_block_pointer, remaining, (inode: Ext2Inode, block: u32, remaining: u32) -> {
			return inode.process_block_entries(block, remaining, (inode: Ext2Inode, block: u32, remaining: u32) -> {
				return inode.process_block_entries(block, remaining, (inode: Ext2Inode, block: u32, remaining: u32) -> {
					inode.blocks.add(block)
					return remaining - 1
				})
			})
		})

		if remaining <= 0 {
			debug.write('Ext2 inode: Finished reading block list with status ') debug.write_line(remaining)
			return remaining
		}

		# If we did not load all blocks, there must be something wrong
		debug.write('Ext2 inode: Could not load all blocks, remaining ') debug.write_line(remaining)
		return EIO
	}

	override can_read(description: OpenFileDescription) { return true }
	override can_write(description: OpenFileDescription) { return true }
	override can_seek(description: OpenFileDescription) { return true }

	override size() {
		return information.size
	}

	# Summary: Writes the specified data at the specified offset into this file
	override write_bytes(bytes: Array<u8>, offset: u64) {
		debug.write_line('Ext2 inode: Writing bytes...')
		panic('Ext2 inode: Writing is not supported yet')
	}

	# Summary: Reads data from this file using the specified offset
	override read_bytes(destination: link, offset: u64, size: u64) {
		debug.write_line('Ext2 inode: Reading bytes...')
		load_block_list()

		# If the specified offset is out of bounds, return an error
		if offset > information.size {
			debug.write_line('Ext2 inode: Offset is out of bounds')
			return EINVAL
		}

		# Truncate the size if it goes past the end of the file
		if offset + size > information.size {
			size = information.size - offset
		}

		if size == 0 {
			debug.write_line('Ext2 inode: Nothing to read')
			return 0
		}

		# Compute the range of blocks we need to read
		first_block_index = offset / block_size
		last_block_index = (offset + size - 1) / block_size
		block_count = last_block_index - first_block_index + 1

		# Add a blocker for this thread, so that we can wait below for all read requests to complete
		process = get_process()
		process.block(Blocker() using KernelHeap)

		tracker = ProgressTracker(process, block_count)

		# Compute where we are inside the first block
		offset_in_block = offset % block_size

		# Do not modify size below, so that we can return the number of bytes read. Instead use another variable.
		remaining = size

		if offset_in_block != 0 {
			# Read the first block, so that we align with the next block
			block = blocks[first_block_index]
			bytes_to_next_block = block_size - offset_in_block
			bytes_to_read = math.min(bytes_to_next_block, remaining)

			file_system.(Ext2).read_block(destination as u64, block, offset_in_block, bytes_to_read, tracker)

			# Move to the next block, because we have read all from the first block
			first_block_index++
			destination += bytes_to_read
			remaining -= bytes_to_read
		}

		# Read the blocks into the destination
		loop (block_index = first_block_index, block_index <= last_block_index, block_index++) {
			block = blocks[block_index]
			bytes_to_read = math.min(block_size, remaining)

			file_system.(Ext2).read_block(destination as u64, block, 0, bytes_to_read, tracker)

			# Update the destination and remaining number of bytes
			destination += bytes_to_read
			remaining -= bytes_to_read
		}

		# Wait for all the read requests to complete
		# Todo: Should this be moved in process?
		file_system.(Ext2).wait()

		debug.write_line('Ext2 inode: Reading is completed')

		# If we succeeded, return the number of read
		if tracker.status == 0 return size

		# Return the error code
		return tracker.status
	}

	override load_status(metadata: FileMetadata) {
		debug.write('Ext2 inode: Loading status of inode ') debug.write_line(index)

		metadata.device_id = file_system.id
		metadata.inode = index
		metadata.mode = information.mode
		metadata.hard_link_count = information.hard_link_count
		metadata.uid = information.uid
		metadata.gid = information.gid
		metadata.represented_device = 0
		metadata.size = information.size
		metadata.block_size = file_system.get_block_size()
		metadata.blocks = (information.size + block_size - 1) / block_size
		metadata.last_access_time = information.last_access_time
		metadata.last_modification_time = information.last_modification_time
		metadata.last_change_time = information.creation_time # Todo: Investigate
		return 0
	}

	destruct() {
		allocator.deallocate(this as link)
	}
}