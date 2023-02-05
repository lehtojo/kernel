namespace kernel.file_systems

plain OpenFileDescription {
	file: File

	is_directory(): bool { return file.is_directory() }

	can_read(): bool { return file.can_read(this) }
	can_write(): bool { return file.can_write(this) }
	can_seek(): bool { return file.can_seek(this) }

	write(data: Array<u8>): u64 {
		if not can_write(this) return -1
		return file.write(this, data)
	}

	read(destination: link, size: u64): u64 {
		if not can_read(this) return -1
		return file.read(this, destination, size)
	}

	seek(offset: u32): i32 {
		if not can_seek(this) return -1
		return file.seek(offset)
	}

	get_directory_entries(): i32 {
		if not is_directory() return -1
		return file.get_directory_entries(this)
	}
}