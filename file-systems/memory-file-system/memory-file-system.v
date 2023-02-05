namespace kernel.file_systems.memory_file_system

import kernel.system_calls

File MemoryObject {
	name: String
}

MemoryObject MemoryFile {
	allocator: Allocator
	name: String
	data: List<u8>

	init(allocator: Allocator, name: String) {
		this.allocator = allocator
		this.name = name
		this.data = List<u8>(allocator) using allocator
	}

	override can_read(description: OpenFileDescription): bool { return true }
	override can_write(description: OpenFileDescription): bool { return true }
	override can_seek(description: OpenFileDescription): bool { return true }

	# Summary: Writes the specified data at the specified offset into this file
	override write(description: OpenFileDescription, new_data: Array<u8>, offset: u64): u64 {
		offset = description.offset
		if data.bounds.outside(offset) return -1

		# Ensure the new data will fit into the file data
		data.reserve(offset + new_data.size)

		memory.copy_into(data, offset, new_data, 0, new_data.size)
		return new_data.size
	}

	# Summary: Reads data from this file using the specified offset
	override read(description: OpenFileDescription, destination: link, size: u64): u64 {
		offset = description.offset
		if data.bounds.outside(offset, size) return -1

		memory.copy(destination, data.data + offset, size)
		return size
	}

	# Summary: Seeks to the specified offset
	override seek(description: OpenFileDescription, offset: u64): i32 {
		return 0
	}

	destruct() {
		data.destruct(allocator)
		allocator.deallocate(this as link)
	}
}

MemoryObject MemoryDirectory {
	allocator: Allocator
	objects: List<MemoryObject>

	init(allocator: Allocator) {
		this.allocator = allocator
		this.objects = List<MemoryObject>(allocator) using allocator
	}

	# Summary: Attempts to find an object with the specified name
	find_object(name: String): MemoryObject {
		loop (i = 0, i < objects.size, i++) {
			# Find an object with the specified name
			object = objects[i]
			if object.name == name return object
		}

		return none as MemoryObject
	}

	# Summary: Creates a new file and adds it to this directory
	create_file(allocator: Allocator, name: String): File {
		file = File(name) using allocator
		objects.add(file)
		return file
	}

	destruct() {
		data.destruct(allocator)
		allocator.deallocate(this as link)
	}
}

PathParts {
	private path: String
	private position: u64

	part: String
	ended => position == path.length

	init(path: String) {
		this.path = path
		this.position = 0
		this.part = 0
	}

	next(): bool {
		# If we have reached the end, there are no parts left
		if position == path.length return false

		separator = path.index_of(`/`, position)

		# If there is no next separator, return the remaining path 
		if separator < 0 {
			part = path.slice(position)
			position = path.length # Go to the end of the path
			return true
		}

		# Store the part before the found separator
		part = path.slice(position, separator)

		# Find the next part after the separator
		position = separator + 1
		return true
	}
}

constant CREATE_OPTION_NONE = 0
constant CREATE_OPTION_FILE = 1
constant CREATE_OPTION_DIRECTORY = 2

FileSystem MemoryFileSystem {
	allocator: Allocator
	root: MemoryDirectory

	# Summary: Produces create options from the specified flags
	get_create_options(flags: u32, is_directory: bool) {
		if not has_flag(flags, O_CREAT) return CREATE_FLAG_NONE

		if is_directory return CREATE_FLAG_DIRECTORY
		return CREATE_OPTION_FILE
	}

	override open_file(base: Custody, path: String, flags: i32, mode: u32): Result<OpenFileDescriptor, u32> {
		custody = open_path(base, path, get_create_options(flags))
		if custody === none return Results.error<OpenFileDescription, u32>(-1)

		description = OpenFileDescription.try_create(custody)
		custody.destruct_until(allocator, base)

		return Results.new<OpenFileDescription, u32>(description)
	}

	override create_file(base: Custody, path: String, flags: i32, mode: u32): Result<OpenFileDescriptor, u32> {
		custody = open_path(base, path, get_create_options(flags))
		if custody === none return Results.error<OpenFileDescription, u32>(-1)

		description = OpenFileDescription.try_create(custody)
		custody.destruct_until(allocator, base)

		return Results.new<OpenFileDescription, u32>(description)
	}

	open make_directory(base: Custody, path: String, flags: i32, mode: u32): Result<OpenFileDescription, u32> {
		custody = open_path(base, path, CREATE_OPTION_DIRECTORY)


	}

	# Summary:
	# Starts from the specified custody, follows the specified path and potentially creates it depending on the specified options.
	# If the end of the path can not be reached, none is returned.
	open_path(container: Custody, path: String, create_options: u8): Custody {
		parts = PathParts.new(path)

		loop {
			if not parts.next() stop

			# Load the current part of the path
			part = parts.part

			# Find a child inode whose name matches the current part
			inode = container.inode.lookup(part)

			# If the child does not exist, we must create it if it is allowed or return none
			if inode === none {
				if create_options == CREATE_FLAG_NONE return none as Custody

				# Create a directory when:
				# - We have not reached the last part in the path (only directories can have childs)
				# - We have reached the last part and it must be a directory
				create_directory = not parts.ended or has_flag(create_options, CREATE_FLAG_DIRECTORY)

				if create_directory {
					inode = container.inode.create_directory(part)
				} else {
					inode = container.inode.create_file(part)
				}

				# Ensure we succeeded at creating the child
				if inode === none return none as Custody
			}

			# Create custody for the current inode
			custody = Custody(part, container, inode) using allocator

			container = custody
		}

		return container
	}
}