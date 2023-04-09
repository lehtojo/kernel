# Summary:
# Represents a buffer that allocates memory using blocks
plain BlockBuffer<T> {
	# The allocator used for allocating blocks
	private allocator: Allocator
	# The capacity of a single block
	private block_capacity: u64
	# The blocks
	private blocks: List<link>
	# The number of elements in the buffer
	readable size: u64

	bounds => Range.new(0, size)

	# Summary: Creates a new block buffer
	init(allocator: Allocator, block_capacity: u64) {
		this.allocator = allocator
		this.block_capacity = block_capacity
		this.blocks = List<link>(allocator) using allocator
		this.size = 0
	}

	# Summary: Ensures the specified number of elements can be stored
	reserve(new_size: u64): _ {
		# Do nothing if we have enough space
		if new_size <= blocks.size * block_capacity return

		# Compute the number of blocks needed
		blocks_needed = (new_size + block_capacity - 1) / block_capacity

		# Compute how many blocks we need to allocate
		blocks_to_allocate = blocks_needed - blocks.size

		# Allocate the new blocks
		loop (i = 0, i < blocks_to_allocate, i++) {
			blocks.add(allocator.allocate<T>(block_capacity))
		}

		# Update the size of this buffer
		size = new_size
	}

	# Summary: Writes the specified number of bytes from the source to the specified offset
	write(offset: u64, source: T*, size: u64): _ {
		# Compute the number of elements that will overflow
		overflow = (offset + size) as i64 - (this.size as i64)

		# If there is overflow, extend the buffer
		if overflow > 0 reserve(this.size + overflow as u64)

		# Compute the block and offset of the first element
		block_index = offset / block_capacity
		block_offset = offset - block_index * block_capacity

		# Compute the number of elements to write into the first block
		write_size = math.min(block_capacity - block_offset, size)

		# Write the elements to the first block
		memory.copy(blocks[block_index] + block_offset, source, write_size)

		# Write remaining elements to the next blocks
		loop {
			# Move over the written elements
			source += write_size
			size -= write_size
			block_index++

			# Stop when there are no more elements to write
			if size == 0 stop

			# Compute the number of elements that can be written to the next block
			write_size = math.min(block_capacity, size)

			# Write the elements to the next block
			memory.copy(blocks[block_index], source, write_size)
		}
	}

	# Summary: Writes the specified number of bytes from the source
	write(offset: u64, source: Array<u8>): _ {
		write(offset, source.data, source.size)
	}

	# Summary: Reads the specified number of bytes from this buffer to the destination
	read(offset: u64, destination: T*, size: u64): _ {
		# Compute the block and offset of the first element
		block_index = offset / block_capacity
		block_offset = offset - block_index * block_capacity

		# Compute the number of elements to read from the first block
		read_size = math.min(block_capacity - block_offset, size)

		# Read the elements from the first block
		memory.copy(destination, blocks[block_index] + block_offset, read_size)

		# Read remaining elements from the next blocks
		loop {
			# Move over the read elements
			destination += read_size
			size -= read_size
			block_index++

			# Stop when there are no more elements to read
			if size == 0 stop

			# Compute the number of elements that can be read from the next block
			read_size = math.min(block_capacity, size)

			# Read the elements from the next block
			memory.copy(destination, blocks[block_index], read_size)
		}
	}

	# Summary: Deallocates the blocks
	deallocate(): _ {
		# Deallocate all blocks
		loop (i = 0, i < blocks.size, i++) {
			allocator.deallocate(blocks[i])
		}

		blocks.clear()
	}

	# Summary: Deallocates blocks and this object
	destruct(): _ {
		deallocate()
		blocks.destruct(allocator)
		allocator.deallocate(this as link)
	}
}