namespace kernel.file_systems

File InodeFile {
	inode: Inode

	init(inode: Inode) {
		this.inode = inode
	}

	override is_directory(description: OpenFileDescription) { return inode.is_directory() }

	override size(description: OpenFileDescription) { return inode.size() }

	override can_read(description: OpenFileDescription) { return true }
	override can_write(description: OpenFileDescription) { return true }
	override can_seek(description: OpenFileDescription) { return true }

	override write(description: OpenFileDescription, data: Array<u8>) {
		debug.write_line('Inode file: Writing bytes...')
		return inode.write_bytes(data, description.offset)
	}
	
	override read(description: OpenFileDescription, destination: link, size: u64) {
		debug.write_line('Inode file: Reading bytes...')
		return inode.read_bytes(destination, description.offset, size)
	}

	override seek(description: OpenFileDescription, offset: u64) {
		return 0
	}
}