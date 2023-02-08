namespace kernel.file_systems

constant SEEK_SET = 0
constant SEEK_CUR = 1
constant SEEK_END = 2

plain OpenFileDescription {
	file: File
	offset: u64 = 0

	shared try_create(allocator, custody: Custody) {
		file: InodeFile = InodeFile(custody.inode) using allocator
		return OpenFileDescription(file) using allocator
	}

	shared try_create(allocator, file: File) {
		return OpenFileDescription(file) using allocator
	}

	init(file: File) {
		this.file = file
	}

	is_directory(): bool { return file.is_directory() }

	can_read(): bool { return file.can_read(this) }
	can_write(): bool { return file.can_write(this) }
	can_seek(): bool { return file.can_seek(this) }

	size(): u64 { return file.size(this) }

	write(data: Array<u8>): u64 {
		if not can_write() return -1
		return file.write(this, data)
	}

	read(destination: link, size: u64): u64 {
		if not can_read() return -1
		return file.read(this, destination, size)
	}

	seek(offset: i64, whence: i32): i32 {
		if not can_seek() {
			debug.write_line('Open file description: Seeking is not allowed')
			return kernel.system_calls.ESPIPE # Todo: Remove full path
		}

		new_offset = 0

		if whence == SEEK_SET {
			new_offset = offset
		} else whence == SEEK_CUR {
			new_offset = this.offset + offset
		} else whence == SEEK_END {
			new_offset = size() + offset
		}

		if new_offset < 0 return {
			debug.write_line('Open file description: Offset became negative')
			kernel.system_calls.EINVAL
		}

		# Warning: Remember to handle cases where seeking past the end is not allowed (normally it is)
		debug.write('Open file description: Setting offset to ') debug.write_line(new_offset)
		this.offset = new_offset

		file.seek(this, new_offset) # Todo: Rename to seeked or did_seek?

		return new_offset
	}

	get_directory_entries(): i32 {
		if not is_directory() return -1
		return file.get_directory_entries(this)
	}
}