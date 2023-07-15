namespace kernel.file_systems.memory_file_system

Inode MemoryInode {
	private constant BLOCK_SIZE = 0x20000

	allocator: Allocator
	name: String
	data: BlockBuffer<u8>

	init(allocator: Allocator, file_system: FileSystem, index: u64, name: String) {
		Inode.init(file_system, index)

		this.allocator = allocator
		this.name = name
		this.data = BlockBuffer<u8>(allocator, BLOCK_SIZE) using allocator
	}

	init(allocator: Allocator, file_system: FileSystem, index: u64, name: String, data: Array<u8>) {
		Inode.init(file_system, index)

		this.allocator = allocator
		this.name = name
		this.data = BlockBuffer<u8>(allocator, BLOCK_SIZE) using allocator
		this.data.write(0, data)
	}

	override can_read(description: OpenFileDescription) { return true }
	override can_write(description: OpenFileDescription) { return true }
	override can_seek(description: OpenFileDescription) { return true }

	override size() {
		return data.size
	}

	# Summary: Writes the specified data at the specified offset into this file
	override write_bytes(bytes: Array<u8>, offset: u64) {
		if data.bounds.outside(offset, 0) {
			debug.write_line('Memory inode: Specified offset out of bounds (write)')
			return -1
		}

		debug.write('Memory inode: Writing ') debug.write(bytes.size) debug.write(' byte(s) to offset ') debug.write_line(offset)

		data.write(offset, bytes)
		return bytes.size
	}

	# Summary: Reads data from this file using the specified offset
	override read_bytes(destination: link, offset: u64, size: u64) {
		if data.bounds.outside(offset, 0) {
			debug.write_line('Memory inode: Specified offset out of bounds (read)')
			return 0
		}

		# Do not read past the end
		remaining = data.size - offset
		size = math.min(remaining, size)

		debug.write('Memory inode: Reading ') debug.write(size) debug.write(' byte(s) from offset ') debug.write_line(offset)

		data.read(offset, destination, size)
		return size
	}

	override load_status(metadata: FileMetadata) {
		# Output debug information
		debug.write('Memory inode: Loading status of inode ') debug.write_line(index)

		# Todo: Fill in correct data
		metadata.device_id = 1
		metadata.inode = index
		metadata.mode = this.metadata.mode | S_IFREG
		metadata.hard_link_count = 1
		metadata.uid = 0
		metadata.gid = 0
		metadata.rdev = 0
		metadata.size = data.size
		metadata.block_size = PAGE_SIZE
		metadata.blocks = (data.size + metadata.block_size - 1) / metadata.block_size
		metadata.last_access_time = 0
		metadata.last_modification_time = 0
		metadata.last_change_time = 0
		return 0
	}

	destruct() {
		data.destruct()
		allocator.deallocate(this as link)
	}
}