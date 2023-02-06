namespace kernel.file_systems

File InodeFile {
	inode: Inode

	init(inode: Inode) {
		this.inode = inode
	}

	override is_directory(description: OpenFileDescription) { return false }

	override can_read(description: OpenFileDescription) { return true }
	override can_write(description: OpenFileDescription) { return true }

	override write(description: OpenFileDescription, data: Array<u8>) {
		return inode.write_bytes(data, description.offset)
	}
	
	override read(description: OpenFileDescription, destination: link, size: u64) {
		return inode.read_bytes(destination, description.offset, size)
	}

	override seek(description: OpenFileDescription, offset: u64) {
		return 0
	}

	override get_directory_entries(description: OpenFileDescription) {
		return -1
	}
}