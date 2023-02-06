namespace kernel.file_systems

Inode {
	open can_read(description: OpenFileDescription): bool { return false }
	open can_write(description: OpenFileDescription): bool { return false }

	open write_bytes(bytes: Array<u8>, offset: u64): u64
	open read_bytes(destination: link, offset: u64, size: u64): u64

	open create_child(name: String): Inode { return none as Inode }

	create_directory(name: String): Inode { return create_child(name) }
	create_file(name: String): Inode { return create_child(name) }

	open lookup(name: String): Inode {
		return none as Inode
	}
}