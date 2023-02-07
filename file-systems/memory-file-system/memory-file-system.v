namespace kernel.file_systems.memory_file_system

import kernel.system_calls

Inode MemoryDirectoryInode {
	private allocator: Allocator
	private name: String
	inodes: List<Inode>

	init(allocator: Allocator, name: String) {
		this.allocator = allocator
		this.name = name
		this.inodes = List<Inode>(allocator) using allocator
	}

	override is_directory() { return true }

	override write_bytes(bytes: Array<u8>, offset: u64) { return -1 }
	override read_bytes(destination: link, offset: u64, size: u64) { return -1 }

	override create_child(name: String) {
		debug.write('Memory directory inode: Creating a child with name ') debug.write_line(name)

		inode = MemoryInode(allocator, name) using allocator
		inodes.add(inode)

		return inode
	}

	override lookup(name: String) {
		debug.write('Memory directory inode: Looking for ') debug.write_line(name)

		# Look for an inode with the specified name
		loop (i = 0, i < inodes.size, i++) {
			inode = inodes[i]
			# Todo: That cast is dirty trick, remove it :D 
			if inode.is_directory() and inode.(MemoryDirectoryInode).name == name return inode
		}

		return none as Inode
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
		this.part = String.empty()

		# Skip the root separator automatically
		if path.starts_with(`/`) { position++ }
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

constant O_CREAT = 0x40

constant CREATE_OPTION_NONE = 0
constant CREATE_OPTION_FILE = 1
constant CREATE_OPTION_DIRECTORY = 2

FileSystem MemoryFileSystem {
	allocator: Allocator

	init(allocator: Allocator) {
		this.allocator = allocator
	}

	# Summary: Produces create options from the specified flags
	get_create_options(flags: u32, is_directory: bool) {
		if not has_flag(flags, O_CREAT) return CREATE_OPTION_NONE

		if is_directory return CREATE_OPTION_DIRECTORY
		return CREATE_OPTION_FILE
	}

	override open_file(base: Custody, path: String, flags: i32, mode: u32) {
		debug.write('Memory file system: Opening file from path ') debug.write_line(path)

		custody = open_path(base, path, get_create_options(flags, false))

		if custody === none {
			debug.write_line('Memory file system: Failed to open the specified path')
			return Results.error<OpenFileDescription, u32>(-1)
		}

		description = OpenFileDescription.try_create(allocator, custody)
		custody.destruct_until(allocator, base)

		return Results.new<OpenFileDescription, u32>(description)
	}

	override create_file(base: Custody, path: String, flags: i32, mode: u32) {
		custody = open_path(base, path, get_create_options(flags, false))
		if custody === none return Results.error<OpenFileDescription, u32>(-1)

		description = OpenFileDescription.try_create(allocator, custody)
		custody.destruct_until(allocator, base)

		return Results.new<OpenFileDescription, u32>(description)
	}

	override make_directory(base: Custody, path: String, flags: i32, mode: u32) {
		custody = open_path(base, path, CREATE_OPTION_DIRECTORY)
		if custody === none return Results.error<OpenFileDescription, u32>(-1)

		description = OpenFileDescription.try_create(allocator, custody)
		custody.destruct_until(allocator, base)

		return Results.new<OpenFileDescription, u32>(description)
	}

	# Summary:
	# Starts from the specified custody, follows the specified path and potentially creates it depending on the specified options.
	# If the end of the path can not be reached, none is returned.
	open_path(container: Custody, path: String, create_options: u8): Custody {
		parts = PathParts(path)

		loop {
			if not parts.next() stop

			# Load the current part of the path
			part = parts.part

			# Find a child inode whose name matches the current part
			inode = container.inode.lookup(part)

			# If the child does not exist, we must create it if it is allowed or return none
			if inode === none {
				if create_options == CREATE_OPTION_NONE return none as Custody

				# Create a directory when:
				# - We have not reached the last part in the path (only directories can have childs)
				# - We have reached the last part and it must be a directory
				create_directory = not parts.ended or has_flag(create_options, CREATE_OPTION_DIRECTORY)

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

export test(allocator: Allocator) {
	file_system = MemoryFileSystem(allocator) using allocator

	root = MemoryDirectoryInode(allocator, String.empty) using allocator
	bin = MemoryDirectoryInode(allocator, String.new('bin')) using allocator
	home = MemoryDirectoryInode(allocator, String.new('home')) using allocator
	user = MemoryDirectoryInode(allocator, String.new('user')) using allocator

	lorem_raw_data = 'Lorem ipsum dolor sit amet'
	lorem_data_size = length_of(lorem_raw_data)
	lorem_data = Array<u8>(lorem_raw_data, lorem_data_size) using allocator
	lorem_inode = MemoryInode(allocator, String.new('lorem.txt')) using allocator
	lorem_file = InodeFile(lorem_inode) using allocator

	root.inodes.add(bin) root.inodes.add(home)
	home.inodes.add(user)
	user.inodes.add(lorem_file.inode)

	Custody.root = Custody(String.empty, none as Custody, root) using allocator
	FileSystem.root = file_system
}