namespace kernel.file_systems

Inode DirectoryInode {
	override write_bytes(bytes: Array<u8>, offset: u64) { return -1 }
	override read_bytes(destination: link, offset: u64, size: u64) { return -1 }

	override lookup(name: String) {
		return none as Inode
	}
}