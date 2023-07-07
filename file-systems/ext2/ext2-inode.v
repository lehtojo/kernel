namespace kernel.file_systems.ext2

Inode Ext2Inode {
	allocator: Allocator
	name: String
	inline information: InodeInformation

	block_size => file_system.(Ext2).block_size

	init(allocator: Allocator, file_system: FileSystem, index: u64, name: String) {
		Inode.init(file_system, index)

		this.allocator = allocator
		this.name = name
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
		require(offset == 0, 'Offset is not supported yet')
	}

	# Summary: Reads data from this file using the specified offset
	override read_bytes(destination: link, offset: u64, size: u64) {
		debug.write_line('Ext2 inode: Reading bytes...')
		require(offset == 0, 'Offset is not supported yet')
	}

	override load_status(metadata: FileMetadata) {
		debug.write('Ext2 inode: Loading status of inode ') debug.write_line(index)

		# Todo: Fill in correct data
		metadata.device_id = 1
		metadata.inode = index
		metadata.mode = this.metadata.mode | S_IFREG
		metadata.hard_link_count = 1
		metadata.uid = 0
		metadata.gid = 0
		metadata.rdev = 0
		metadata.size = information.size
		metadata.block_size = PAGE_SIZE
		metadata.blocks = (information.size + block_size - 1) / block_size
		metadata.last_access_time = 0
		metadata.last_modification_time = 0
		metadata.last_change_time = 0
		return 0
	}

	destruct() {
		allocator.deallocate(this as link)
	}
}