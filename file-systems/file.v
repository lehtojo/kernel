namespace kernel.file_systems

File {
	open is_directory(description: OpenFileDescription): bool { return false }

	open can_read(description: OpenFileDescription): bool { return false }
	open can_write(description: OpenFileDescription): bool { return false }

	open write(description: OpenFileDescription, data: Array<u8>): u64 { return -1 }
	open read(description: OpenFileDescription, destination: link, size: u64): u64 { return -1 }
	open seek(description: OpenFileDescription, offset: u64): i32 { return -1 }

	open get_directory_entries(description: OpenFileDescription): i32 { return -1 }
}