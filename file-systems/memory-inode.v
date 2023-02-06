namespace kernel.file_systems

Inode MemoryInode {
	allocator: Allocator
	name: String
	data: List<u8>

	init(allocator: Allocator, name: String) {
		this.allocator = allocator
		this.name = name
		this.data = List<u8>(allocator) using allocator
	}

	override can_read(description: OpenFileDescription) { return true }
	override can_write(description: OpenFileDescription) { return true }

	# Summary: Writes the specified data at the specified offset into this file
	override write_bytes(bytes: Array<u8>, offset: u64) {
		if data.bounds.outside(offset, 0) {
			debug.write_line('Memory inode: Specified offset out of bounds (write)')
			return -1
		}

		debug.write('Memory inode: Writing ') debug.write(bytes.size) debug.write(' byte(s) to offset ') debug.write_line(offset)

		# Ensure the new data will fit into the file data
		data.reserve(offset + bytes.size)

		memory.copy_into(data, offset, bytes, 0, bytes.size)
		return bytes.size
	}

	# Summary: Reads data from this file using the specified offset
	open read_bytes(destination: link, offset: u64, size: u64) {
		offset = description.offset

		if data.bounds.outside(offset, size) {
			debug.write_line('Memory inode: Specified offset out of bounds (read)')
			return -1
		}

		debug.write('Memory inode: Reading ') debug.write(size) debug.write(' byte(s) from offset ') debug.write_line(offset)

		memory.copy(destination, data.data + offset, size)
		return size
	}

	destruct() {
		data.destruct(allocator)
		allocator.deallocate(this as link)
	}
}