namespace kernel.file_systems

Inode {
	readable file_system: FileSystem
	readable index: u64

	init(file_system: FileSystem, index: u64) {
		this.file_system = file_system
		this.index = index
	}

	identifier => InodeIdentifier.new(file_system.index, index)

	open is_directory(): bool { return false }

	open can_read(description: OpenFileDescription): bool { return false }
	open can_write(description: OpenFileDescription): bool { return false }

	open size(): u64 { return 0 }

	open write_bytes(bytes: Array<u8>, offset: u64): u64
	open read_bytes(destination: link, offset: u64, size: u64): u64

	open create_child(name: String, is_directory: bool): Inode { return none as Inode }

	create_directory(name: String): Inode { return create_child(name, true) }
	create_file(name: String): Inode { return create_child(name, false) }

	open lookup(name: String): Inode { return none as Inode }

	open load_status(metadata: FileMetadata): u32 { return -1 }
}