namespace kernel.file_systems

File {
	open is_directory(description: OpenFileDescription): bool { return false }

	open can_read(description: OpenFileDescription): bool { return false }
	open can_write(description: OpenFileDescription): bool { return false }
	open can_seek(description: OpenFileDescription): bool { return false }

	open size(description: OpenFileDescription): u64 { return 0 }

	open write(description: OpenFileDescription, data: Array<u8>, offset: u64): u64 { return -1 }
	open read(description: OpenFileDescription, destination: link, offset: u64, size: u64): u64 { return -1 }
	open seek(description: OpenFileDescription, offset: u64): i32 { return -1 }

	open close(): u32 { return 0 }
}