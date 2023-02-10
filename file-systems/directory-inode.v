namespace kernel.file_systems

Inode DirectoryInode {
	init(file_system: FileSystem, index: u64) {
		Inode.init(file_system, index)
	}

	override is_directory() { return true }

	override write_bytes(bytes: Array<u8>, offset: u64) { return -1 }
	override read_bytes(destination: link, offset: u64, size: u64) { return -1 }

	override lookup(name: String) {
		return none as Inode
	}
}