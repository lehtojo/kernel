namespace kernel.file_systems

File InodeFile {
	readable inode: Inode
	readable subscribers: Subscribers

	init(inode: Inode) {
		this.inode = inode
		this.subscribers = Subscribers.new(HeapAllocator.instance)
	}

	override is_inode() { return true }
	override is_directory(description: OpenFileDescription) { return inode.is_directory() }

	override subscribe(blocker: Blocker) { subscribers.subscribe(blocker) }
	override unsubscribe(blocker: Blocker) { subscribers.unsubscribe(blocker) }

	override size(description: OpenFileDescription) { return inode.size() }

	override can_read(description: OpenFileDescription) { return true }
	override can_write(description: OpenFileDescription) { return true }
	override can_seek(description: OpenFileDescription) { return true }

	override write(description: OpenFileDescription, data: Array<u8>, offset: u64) {
		debug.write_line('Inode file: Writing bytes...')

		result = inode.write_bytes(data, offset)

		subscribers.update()
		return result
	}
	
	override read(description: OpenFileDescription, destination: link, offset: u64, size: u64) {
		debug.write_line('Inode file: Reading bytes...')

		result = inode.read_bytes(destination, offset, size)

		subscribers.update()
		return result
	}

	override seek(description: OpenFileDescription, offset: u64) {
		subscribers.update()
		return 0
	}

	override load_status(metadata: FileMetadata) {
		return inode.load_status(metadata)
	}
}