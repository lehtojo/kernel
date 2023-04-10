namespace kernel.file_systems

constant SEEK_SET = 0
constant SEEK_CUR = 1
constant SEEK_END = 2

pack DirectoryEntry64 {
	inode: u64
	offset: u64
	size: u16
	type: u8

	shared new(inode: u64, offset: u64, size: u16, type: u8): DirectoryEntry64 {
		return pack { inode: inode, offset: offset, size: size, type: type } as DirectoryEntry64
	}
}

pack TimeSpecification {
	seconds: u64
	nanoseconds: u32
}

plain FileMetadata {
	device_id: u32
	padding_1: u32
	inode: u64
	mode: u16
	padding_2: u16
	hard_link_count: u32
	uid: u32
	gid: u32
	rdev: u32
	padding_3: u32
	size: u64
	block_size: u32
	blocks: u32
	last_access_time: TimeSpecification
	last_modification_time: TimeSpecification
	last_change_time: TimeSpecification
}

plain OpenFileDescription {
	import kernel.system_calls

	file: File
	offset: u64 = 0
	custody: Custody

	shared try_create(allocator, custody: Custody) {
		file: InodeFile = InodeFile(custody.inode) using allocator
		description = OpenFileDescription(file) using allocator
		description.custody = custody
		return description
	}

	shared try_create(allocator, file: File) {
		# Todo: Verify the specified file is not file system based, because we always want the custody 
		return OpenFileDescription(file) using allocator
	}

	init(file: File) {
		this.file = file
	}

	is_directory(): bool { return file.is_directory(this) }

	can_read(): bool { return file.can_read(this) }
	can_write(): bool { return file.can_write(this) }
	can_seek(): bool { return file.can_seek(this) }

	size(): u64 { return file.size(this) }

	write(data: Array<u8>, offset: u64): u64 {
		if not can_write() return -1
		return file.write(this, data, offset)
	}

	write(data: Array<u8>): u64 {
		return write(data, offset)
	}

	read(destination: link, offset: u64, size: u64): u64 {
		if not can_read() return -1
		return file.read(this, destination, offset, size)
	}

	read(destination: link, size: u64): u64 {
		return read(destination, offset, size)
	}

	seek(offset: i64, whence: i32): i32 {
		if not can_seek() {
			debug.write_line('Open file description: Seeking is not allowed')
			return ESPIPE
		}

		new_offset = 0

		if whence == SEEK_SET {
			new_offset = offset
		} else whence == SEEK_CUR {
			new_offset = this.offset + offset
		} else whence == SEEK_END {
			new_offset = size() + offset
		}

		if new_offset < 0 {
			debug.write_line('Open file description: Offset became negative')
			return EINVAL
		}

		# Warning: Remember to handle cases where seeking past the end is not allowed (normally it is)
		debug.write('Open file description: Setting offset to ') debug.write_line(new_offset)
		this.offset = new_offset

		file.seek(this, new_offset) # Todo: Rename to seeked or did_seek?

		return new_offset
	}

	load_status(metadata: FileMetadata): u32 {
		return file.load_status(metadata)
	}

	get_directory_entries(output: MemoryRegion): u64 {
		if not is_directory() {
			debug.write_line('Open file description: Can not get directory entries, because the opened file is not a directory')
			return ENOTDIR
		}

		# Todo: Figure out if this is safe: Because the opened file is a directory, we assume that the file must be an inode file
		inode = file.(InodeFile).inode
		allocator = LocalHeapAllocator(HeapAllocator.instance)
		error = 0

		debug.write_line('Open file description: Iterating directory entries...')

		loop entry in FileSystem.root.iterate_directory(allocator, inode) {
			debug.write('Open file description: Found directory entry: name=')
			debug.write(entry.name)
			debug.write(', inode=')
			debug.write_line(entry.inode.index)

			# Compute the size of the output data structure with the name, align it to 8 bytes
			unaligned_output_entry_size = sizeof(DirectoryEntry64) + entry.name.length + 1
			output_entry_size = memory.round_to(sizeof(DirectoryEntry64) + entry.name.length + 1, 8)
			padding = output_entry_size - unaligned_output_entry_size

			# Compute the offset to the next entry
			next_entry_offset = output.position + output_entry_size

			output_entry = DirectoryEntry64.new(
				entry.inode.index,
				next_entry_offset,
				output_entry_size,
				entry.type
			)

			# Output the current entry data
			if not output.write_and_advance<DirectoryEntry64>(output_entry) {
				debug.write_line('Open file description: Userspace buffer was too small for directory entries')
				error = EINVAL # Tell the user the output buffer is too small
				stop
			}

			# Output the name of the current entry and zero terminate it
			if not output.write_string_and_advance(entry.name, true) {
				debug.write_line('Open file description: Userspace buffer was too small for directory entries')
				error = EINVAL # Tell the user the output buffer is too small
				stop
			}

			# Move over the padding
			# Note: It is a bit dumb if the last entry is written, but the padding fails the whole system call, but 
			# the idea is that the offset should never point outside the userspace buffer and currently even the 
			# last entry has an offset that points to the "next entry". 
			if not output.advance(padding) {
				debug.write_line('Open file description: Userspace buffer was too small for directory entries')
				error = EINVAL # Tell the user the output buffer is too small
				stop
			}
		}

		allocator.deallocate()

		debug.write_line('Open file description: Finished iterating directory entries')

		# Return the error code if it was set
		if error return error

		debug.write('Open file description: Wrote directory entries ') debug.write(output.position) debug.write_line(' byte(s) into userspace')

		# Return the number of bytes written to the output
		return output.position
	}

	close(): u32 {
		return file.close()
	}
}