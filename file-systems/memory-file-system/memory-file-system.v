namespace kernel.file_systems.memory_file_system

import kernel.system_calls
import kernel.devices

Inode MemoryDirectoryInode {
	private allocator: Allocator
	private name: String
	inodes: List<Inode>

	init(allocator: Allocator, file_system: FileSystem, index: u64, name: String) {
		Inode.init(file_system, index)

		this.allocator = allocator
		this.name = name
		this.inodes = List<Inode>(allocator) using allocator
	}

	override is_directory() { return true }

	override write_bytes(bytes: Array<u8>, offset: u64) { return -1 }
	override read_bytes(destination: link, offset: u64, size: u64) { return -1 }

	override create_child(name: String, mode: u16, device: u64) {
		# Output debug information
		is_device = has_flag(mode, S_IFCHR) or has_flag(mode, S_IFBLK)

		if is_device {
			debug.write('Memory directory inode: Creating a device ')
			debug.write(device)
			debug.write(' with name ')
			debug.write_line(name)
		} else {
			debug.write('Memory directory inode: Creating a child with name ') debug.write_line(name)
		}

		# Allocate an inode index for the child
		child_index = file_system.allocate_inode_index()
		if child_index == -1 return none as Inode

		inode = none as Inode
		is_directory = (mode & S_IFMT) == S_IFDIR

		# Create a directory or a normal inode based on the arguments
		if is_directory { inode = MemoryDirectoryInode(allocator, file_system, child_index, name.copy(allocator)) using allocator }
		else { inode = MemoryInode(allocator, file_system, child_index, name.copy(allocator)) using allocator }

		# Save metadata
		inode.metadata.mode = mode

		# If we are creating a device, write the device major and minor numbers
		if is_device { inode.metadata.device = device }

		inodes.add(inode)

		return inode
	}

	override lookup(name: String) {
		debug.write('Memory directory inode: Looking for ') debug.write_line(name)

		# If the name is ".", return this directory
		if name == '.' return this

		# Look for an inode with the specified name
		loop (i = 0, i < inodes.size, i++) {
			inode = inodes[i]
			# Todo: That cast is dirty trick, remove it :D 
			if inode.is_directory() and inode.(MemoryDirectoryInode).name == name return inode
			if not inode.is_directory() and inode.(MemoryInode).name == name return inode
		}

		return none as Inode
	}

	override load_status(metadata: FileMetadata) {
		# Output debug information
		debug.write('Memory directory inode: Loading status of inode ') debug.write_line(index)

		# Todo: Fill in correct data
		metadata.device_id = 1
		metadata.inode = index
		metadata.mode = this.metadata.mode | S_IFDIR
		metadata.hard_link_count = 1
		metadata.uid = 0
		metadata.gid = 0
		metadata.rdev = 0
		metadata.size = 0
		metadata.block_size = PAGE_SIZE
		metadata.blocks = 1 
		metadata.last_access_time = 0
		metadata.last_modification_time = 0
		metadata.last_change_time = 0
		return 0
	}
}

DirectoryIterator MemoryDirectoryIterator {
	private entry: DirectoryEntry
	private directory: MemoryDirectoryInode
	private entry_index: u32 = -1

	init(entry: DirectoryEntry, directory: MemoryDirectoryInode) {
		this.entry = entry
		this.directory = directory
	}

	override next() {
		if ++entry_index >= directory.inodes.size return false 

		inode = directory.inodes[entry_index] as MemoryInode
		entry.name = inode.name
		entry.inode = inode
		entry.type = DT_REG # Todo: Figure out the type

		return true
	}

	override value() {
		return entry
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

constant CREATE_OPTION_NONE = 0
constant CREATE_OPTION_FILE = 1
constant CREATE_OPTION_DIRECTORY = 2

FileSystem MemoryFileSystem {
	allocator: Allocator
	devices: Devices
	inode_index: u64

	init(allocator: Allocator, devices: Devices) {
		this.allocator = allocator
		this.devices = devices
	}

	# Summary: Produces create options from the specified flags
	get_create_options(flags: u32, is_directory: bool) {
		if not has_flag(flags, O_CREAT) return CREATE_OPTION_NONE

		if is_directory return CREATE_OPTION_DIRECTORY
		return CREATE_OPTION_FILE
	}

	override open_file(base: Custody, path: String, flags: i32, mode: u32) {
		debug.write('Memory file system: Opening file from path ') debug.write_line(path)

		local_allocator = LocalHeapAllocator(HeapAllocator.instance)

		result = open_path(local_allocator, base, path, get_create_options(flags, false))

		if result.has_error {
			debug.write_line('Memory file system: Failed to open the specified path')
			local_allocator.deallocate()
			return Results.error<OpenFileDescription, u32>(result.error)
		}

		custody = result.value
		description = none as OpenFileDescription

		# Extract metadata of the inode
		metadata = custody.inode.metadata

		# If the inode represents a device, let the device handle the opening
		if metadata.is_device {
			# Find the device represented by the inode
			if devices.find(metadata.device) has not device {
				return Results.error<OpenFileDescription, u32>(ENXIO)
			}

			description = device.create_file_description(allocator, custody)

		} else {
			# Create the file description using the custody
			description = OpenFileDescription.try_create(allocator, custody)
		}

		local_allocator.deallocate()
		return Results.new<OpenFileDescription, u32>(description)
	}

	override create_file(base: Custody, path: String, flags: i32, mode: u32) {
		local_allocator = LocalHeapAllocator(HeapAllocator.instance)

		result = open_path(local_allocator, base, path, get_create_options(flags, false))

		if result.has_error {
			local_allocator.deallocate()
			return Results.error<OpenFileDescription, u32>(result.error)
		}

		custody = result.value
		inode = custody.inode
		require(inode !== none, 'Created file did not have an inode')
	
		inode.metadata.mode = mode

		description = OpenFileDescription.try_create(allocator, custody)

		local_allocator.deallocate()
		return Results.new<OpenFileDescription, u32>(description)
	}

	override make_directory(base: Custody, path: String, flags: i32, mode: u32) {
		local_allocator = LocalHeapAllocator(HeapAllocator.instance)

		result = open_path(local_allocator, base, path, CREATE_OPTION_DIRECTORY)

		if result.has_error {
			local_allocator.deallocate()
			return Results.error<OpenFileDescription, u32>(result.error)
		}

		custody = result.value
		inode = custody.inode
		require(inode !== none, 'Created directory did not have an inode')
	
		inode.metadata.mode = mode

		description = OpenFileDescription.try_create(allocator, custody)

		local_allocator.deallocate()
		return Results.new<OpenFileDescription, u32>(description)
	}

	override access(base: Custody, path: String, mode: u32) {
		debug.write('Memory file system: Accessing path ') debug.write_line(path)

		local_allocator = LocalHeapAllocator(HeapAllocator.instance)
		result = open_path(local_allocator, base, path, CREATE_OPTION_NONE)

		if result.has_error {
			debug.write_line('Memory file system: Failed to access the path')
			local_allocator.deallocate()
			return result.error
		}

		debug.write_line('Memory file system: Accessed the path successfully')
		local_allocator.deallocate()
		return F_OK
	}

	override lookup_status(base: Custody, path: String, metadata: FileMetadata) {
		debug.write_line('Memory file system: Lookup metadata')

		local_allocator = LocalHeapAllocator(HeapAllocator.instance)

		# Attempt to open the specified path
		open_result = open_path(local_allocator, base, path, CREATE_OPTION_NONE)

		if open_result.has_error {
			debug.write_line('Memory file system: Failed to lookup metadata')
			local_allocator.deallocate()
			return open_result.error
		}

		# Load file status using the inode from the custody
		custody = open_result.value
		result = custody.inode.load_status(metadata)

		# Deallocate and return the result code
		local_allocator.deallocate()
		return result
	}

	override lookup_extended_status(base: Custody, path: String, metadata: FileMetadataExtended) {
		standard_metadata = FileMetadata()
		lookup_status(base, path, standard_metadata)

		metadata.mask = 0
		metadata.block_size = standard_metadata.block_size
		metadata.attributes = 0
		metadata.hard_link_count = standard_metadata.hard_link_count
		metadata.uid = standard_metadata.uid
		metadata.gid = standard_metadata.gid
		metadata.mode = standard_metadata.mode
		metadata.inode = standard_metadata.inode
		metadata.size = standard_metadata.size
		metadata.blocks = standard_metadata.blocks
		metadata.attributes_mask = 0
		metadata.last_access_time = 0 as Timestamp
		metadata.creation_time = 0 as Timestamp
		metadata.last_change_time = 0 as Timestamp
		metadata.last_modification_time = 0 as Timestamp
		metadata.device_major = standard_metadata.rdev |> 32
		metadata.device_minor = standard_metadata.rdev & 0xffffffff
		metadata.file_system_device_major = standard_metadata.device_id |> 32
		metadata.file_system_device_minor = standard_metadata.device_id & 0xffffffff
		metadata.mount_id = 0
		return 0
	} 

	override iterate_directory(allocator: Allocator, inode: Inode) {
		require(inode.is_directory(), 'Specified inode was not a directory')

		entry = DirectoryEntry() using allocator
		return MemoryDirectoryIterator(entry, inode as MemoryDirectoryInode) using allocator
	}

	override allocate_inode_index() {
		return inode_index++
	}

	# Summary:
	# Starts from the specified custody, follows the specified path and potentially creates it depending on the specified options.
	# If the end of the path can not be reached, none is returned.
	override open_path(allocator: Allocator, container: Custody, path: String, create_options: u8) {
		parts = PathParts(path)

		loop {
			if not parts.next() stop

			# Load the current part of the path
			part = parts.part

			# Skip empty path parts
			if part.length == 0 continue

			# Find a child inode whose name matches the current part
			inode = container.inode.lookup(part)

			# If the child does not exist, we must create it if it is allowed or return none
			if inode === none {
				if create_options == CREATE_OPTION_NONE return Results.error<Custody, u32>(ENOENT)

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
				if inode === none return Results.error<Custody, u32>(EIO)
			}

			# Create custody for the current inode
			custody = Custody(part, container, inode) using allocator

			container = custody
		}

		return Results.new<Custody, u32>(container)
	}
}

pack BootFileHeader {
	path: link
	size: u64
	data: link

	shared new(path: link, size: u64, data: link): BootFileHeader {
		return pack { path: path, size: size, data: data } as BootFileHeader
	}
}

# Summary: Loads memory file system boot files from the specified memory region
load_boot_file_headers(allocator, start: link, end: link): List<BootFileHeader> {
	headers = List<BootFileHeader>(allocator) using allocator

	loop (start + sizeof(u64) * 2 < end) {
		path = start.(u64*)[0] as link
		size = start.(u64*)[1]

		# Create a file header for the current file and map the addresses so that we can read from them
		header = BootFileHeader.new(
			mapper.to_kernel_virtual_address(path),
			size,
			start + sizeof(u64) * 2
		)

		debug.write('Memory file system: Boot file: path=')
		debug.write(header.path)
		debug.write(', size=')
		debug.write(size)
		debug.write(', data=')
		debug.write_address(header.data)
		debug.write_line()

		headers.add(header)

		# Move over the current file
		start += sizeof(u64) * 2 + size
	}

	return headers
}

# Summary: Loads the files into memory based on their headers
load_files_into_memory(file_system: FileSystem, headers: List<BootFileHeader>) {
	debug.write_line('Memory file system: Copying the boot files into memory...')

	mode = S_IRWXU | S_IRWXG | S_IRWXO # Read, write, execute for all

	loop (i = 0, i < headers.size, i++) {
		header = headers[i]
		path = String.new(header.path)

		# Create the file and then write its contents
		if file_system.create_file(Custody.root, path, O_CREAT | O_WRONLY, mode) has not descriptor {
			panic('Failed to create boot file')
		}

		# Write the contents and then close
		require(descriptor.write(Array<u8>(header.data, header.size)) == header.size, 'Failed to write the boot file into memory')

		descriptor.close()
	}

	debug.write_line('Memory file system: Finished copying the boot files into memory')
}

export load_boot_files(allocator: Allocator, file_system: FileSystem, memory_information: SystemMemoryInformation) {
	symbols = memory_information.symbols
	start_symbol_name = 'memory_file_system_start'
	end_symbol_name = 'memory_file_system_end'

	# Find the symbol that marks the start of the memory file system
	start_symbol_index = symbols.find_index<link>(start_symbol_name, (i: SymbolInformation, symbol: link) -> i.name == symbol)
	end_symbol_index = symbols.find_index<link>(end_symbol_name, (i: SymbolInformation, symbol: link) -> i.name == symbol)
	require(start_symbol_index >= 0 and end_symbol_index >= 0, 'Failed to find the boot memory file system')

	# Load the symbols so that we know where to load the files
	start_symbol = symbols[start_symbol_index]
	end_symbol = symbols[end_symbol_index]

	debug.write('Memory file system: Boot data start = ') debug.write_address(start_symbol.address) debug.write_line()
	debug.write('Memory file system: Boot data end = ') debug.write_address(end_symbol.address) debug.write_line()

	# Map the symbols addresses so that can we read between them
	mapped_start_symbol = mapper.to_kernel_virtual_address(start_symbol.address)
	mapped_end_symbol = mapper.to_kernel_virtual_address(end_symbol.address)

	loader_allocator = LocalHeapAllocator(allocator)

	headers = load_boot_file_headers(loader_allocator, mapped_start_symbol, mapped_end_symbol)
	load_files_into_memory(file_system, headers)

	loader_allocator.deallocate()
}

# Summary: Adds all the specified devices to the specified device directory
export add_devices_to_folder(device_directory: MemoryDirectoryInode, devices: List<Device>): _ {
	loop (i = 0, i < devices.size, i++) {
		device = devices[i]

		# Todo: Support other device types
		device_directory.create_character_device(device.get_name(), device.identifier)	
	}	
}

export test(allocator: Allocator, memory_information: SystemMemoryInformation, devices: Devices) {
	file_system = MemoryFileSystem(allocator, devices) using allocator

	root = MemoryDirectoryInode(allocator, file_system, file_system.allocate_inode_index(), String.empty) using allocator
	bin = MemoryDirectoryInode(allocator, file_system, file_system.allocate_inode_index(), String.new('bin')) using allocator
	home = MemoryDirectoryInode(allocator, file_system, file_system.allocate_inode_index(), String.new('home')) using allocator
	user = MemoryDirectoryInode(allocator, file_system, file_system.allocate_inode_index(), String.new('user')) using allocator
	dev = MemoryDirectoryInode(allocator, file_system, file_system.allocate_inode_index(), String.new('dev')) using allocator

	lorem_raw_data = 'Lorem ipsum dolor sit amet'
	lorem_data_size = length_of(lorem_raw_data)
	lorem_data = Array<u8>(lorem_raw_data, lorem_data_size)
	lorem_index = file_system.allocate_inode_index()
	lorem_inode = MemoryInode(allocator, file_system, lorem_index, String.new('lorem.txt'), lorem_data) using allocator
	lorem_file = InodeFile(lorem_inode) using allocator

	root.inodes.add(bin) root.inodes.add(home) root.inodes.add(dev)
	home.inodes.add(user)
	user.inodes.add(lorem_file.inode)

	# Add all the devices to the device directory
	device_list = List<Device>(allocator)
	devices.get_all(device_list)
	add_devices_to_folder(dev, device_list)
	device_list.clear()

	Custody.root = Custody(String.empty, none as Custody, root) using allocator
	FileSystem.root = file_system

	load_boot_files(allocator, file_system, memory_information)
}