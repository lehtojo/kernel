namespace kernel.file_systems.ext2

import kernel.devices.storage
import kernel.system_calls
import kernel.devices

FileSystemRequest {
	inode: u64
	address: u64
	size: u64
	commited: u64[1]
	progress: u64[1]
	end: u64[1]

	init(inode: u64, address: u64, size: u64) {
		this.inode = inode
		this.address = address
		this.size = size
		this.end[] = size
	}

	open complete(status: u16): _ {
		debug.write_line('File system request: Completed')
	}
}

pack ReadRequest {
	caller: Ext2
	request: FileSystemRequest
	process: Process
	inode_inside_block_byte_offset: u32
}

pack Ext2DirectoryEntry {
	inode: u32
	size: u16
	name_length: u8
	type: u8
}

DirectoryIterator Ext2DirectoryIterator {
	private allocator: Allocator
	private data: Ext2DirectoryEntry*
	private end: Ext2DirectoryEntry*
	private inline entry: DirectoryEntry

	init(allocator: Allocator, data: Ext2DirectoryEntry*, end: Ext2DirectoryEntry*) {
		this.allocator = allocator
		this.data = data
		this.end = end
	}

	override next() {
		# If the previous entry has a name, deallocate it
		if entry.name.data !== none {
			allocator.deallocate(entry.name.data)
		}

		if data >= end return false

		# Load the name length
		name_length: u64 = data[].name_length

		# Allocate memory for the name
		name = allocator.allocate(name_length + 1)

		if name === none return false

		# Copy the name
		memory.copy(name, (data + sizeof(Ext2DirectoryEntry)) as u8*, name_length)

		entry.name = String.new(name, name_length)
		entry.inode = data[].inode
		entry.type = when (data[].type) {
			1 => DT_REG,
			2 => DT_DIR,
			3 => DT_CHR,
			4 => DT_BLK,
			5 => DT_FIFO,
			6 => DT_SOCK,
			7 => DT_LNK,
			else => DT_UNKNOWN
		}

		# Go past this entry using the size field
		data += data[].size

		# Finally, align the data pointer to the next 4-byte boundary
		data = memory.round_to(data, 4)

		return true
	}

	override value() {
		return entry
	}
}

FileSystem Ext2 {
	shared instance: Ext2
	shared root_inode: Inode

	constant MIN_SUPPORTED_MAJOR_VERSION = 1

	allocator: Allocator
	devices: Devices
	device: BlockStorageDevice
	superblock: Superblock = none as Superblock
	block_group_descriptors: List<BlockGroupDescriptor> = none as List<BlockGroupDescriptor>
	block_group_descriptor_inode_usage_bitmaps: List<link> = none as List<link>

	block_size => 1 <| (superblock.formatted_block_size + 10)
	fragment_size => 1 <| (superblock.formatted_fragment_size + 10)

	init(allocator: Allocator, devices: Devices, device: BlockStorageDevice) {
		this.allocator = allocator
		this.devices = devices
		this.device = device
		this.index = SIGNATURE # Todo: Remove
	}

	initialize(): u64 {
		return load_superblock()
	}

	private load_superblock(): u64 {
		debug.write_line('Ext2: Loading the superblock...')

		# Allocate memory for loading the superblock
		superblock_device_size = memory.round_to(sizeof(Superblock), device.block_size)
		superblock_physical_address = PhysicalMemoryManager.instance.allocate_physical_region(superblock_device_size)
		if superblock_physical_address === none return ENOMEM

		superblock = mapper.map_kernel_page(superblock_physical_address) as Superblock

		callback = (status: u16, request: BaseRequest<Ext2>) -> {
			if status != 0 {
				debug.write_line('Ext2: Failed to load the superblock')
				return true
			}
	
			request.data.process_superblock_and_continue()
			return true

		} as (u16, BlockDeviceRequest) -> bool

		request = BaseRequest<Ext2>(allocator, superblock_physical_address as u64, callback) using allocator
		request.data = this
		request.block_index = SUPERBLOCK_OFFSET / device.block_size
		request.set_device_region_size(device, sizeof(Superblock))

		device.read(request)
		return 0
	}

	private process_superblock_and_continue(): _ {
		debug.write_line('Ext2: Superblock: ')
		debug.write('  Number of inodes: ') debug.write_line(superblock.inode_count)
		debug.write('  Number of blocks: ') debug.write_line(superblock.block_count)
		debug.write('  Number of superuser reserved blocks: ') debug.write_line(superblock.superuser_reserved_block_count)
		debug.write('  Number of unallocated blocks: ') debug.write_line(superblock.unallocated_block_count)
		debug.write('  Number of unallocated inodes: ') debug.write_line(superblock.unallocated_inode_count)
		debug.write('  Block that contains the superblock: ') debug.write_line(superblock.block_containing_superblock)
		debug.write('  Block size: ') debug.write_line(block_size)
		debug.write('  Fragment size: ') debug.write_line(fragment_size)
		debug.write('  Number of blocks in block group: ') debug.write_line(superblock.blocks_in_block_group)
		debug.write('  Number of fragments in block group: ') debug.write_line(superblock.fragments_in_block_group)
		debug.write('  Number of inodes in block group: ') debug.write_line(superblock.inodes_in_block_group)
		debug.write('  Last mount time: ') debug.write_line(superblock.last_mount_time)
		debug.write('  Last written time: ') debug.write_line(superblock.last_written_time)
		debug.write('  Number of mount since last consistency check: ') debug.write_line(superblock.mount_count_since_last_consistency_check)
		debug.write('  Max allowed mounts before consistency check: ') debug.write_line(superblock.max_allowed_mounts_before_consistency_check)
		debug.write('  Signature: ') debug.write_address(superblock.signature) debug.write_line()
		debug.write('  File system state: ') debug.write_line(superblock.file_system_state)
		debug.write('  Error handling method: ') debug.write_line(superblock.error_handling_method)
		debug.write('  Minor version: ') debug.write_line(superblock.minor_version)
		debug.write('  Last consistency check time: ') debug.write_line(superblock.last_consistency_check_time)
		debug.write('  Forced consistency check interval: ') debug.write_line(superblock.forced_consistency_check_interval)
		debug.write('  Creator OS id: ') debug.write_line(superblock.creator_operating_system_id)
		debug.write('  Major version: ') debug.write_line(superblock.major_version)
		debug.write('  User id: ') debug.write_line(superblock.user_id)
		debug.write('  Group id: ') debug.write_line(superblock.group_id)
		debug.write('  Inode size: ') debug.write_line(superblock.inode_size)
	
		if superblock.signature != SIGNATURE {
			debug.write_line('Ext2: Error: Invalid signature')
			return
		}

		# We do not support versions below 1.0 as some fields are not available such as 64-bit file size
		if superblock.major_version < MIN_SUPPORTED_MAJOR_VERSION {
			debug.write_line('Ext2: Error: Too old file system')
			return
		}

		# Verify the inode size is sensible. If the block size is not multiple of inode sizes,
		# then it might be possible that inode information is across two blocks, which is not supported.
		if not memory.is_aligned(block_size, superblock.inode_size) {
			debug.write_line('Ext2: Error: Block size is not multiple of inode size')
			return
		}

		# Standard requires that inode usage bitmap must fit inside a single block
		if memory.round_to(superblock.inodes_in_block_group, 8) / 8 > block_size {
			debug.write_line('Ext2: Error: Inode usage bitmap does not fit inside a single block')
			return
		}

		load_block_group_descriptors()
	}

	private load_block_group_descriptors(): u64 {
		# Compute how many block groups there are
		total_blocks = superblock.block_count + superblock.unallocated_block_count
		total_block_groups = (total_blocks + superblock.blocks_in_block_group - 1) / superblock.blocks_in_block_group # ceil(total_blocks / blocks_in_block_group)
		debug.write('Ext2: Total number of block groups: ') debug.write_line(total_block_groups)

		# Allocate memory into which we copy the descriptors
		block_groups_memory_size = memory.round_to(total_block_groups * sizeof(BlockGroupDescriptor), device.block_size)
		block_group_descriptors_physical_address = PhysicalMemoryManager.instance.allocate_physical_region(block_groups_memory_size)
		if block_group_descriptors_physical_address === none return ENOMEM

		# Compute the byte offset of the block group descriptors
		superblock_block_index = SUPERBLOCK_OFFSET / block_size
		block_group_descriptors_block_index = superblock_block_index + 1
		block_group_descriptors_offset = block_group_descriptors_block_index * block_size

		# Map the descriptor memory so that we can access it using a list
		mapped_block_group_descriptors = mapper.map_kernel_region(block_group_descriptors_physical_address, block_groups_memory_size)
		block_group_descriptors = List<BlockGroupDescriptor>(allocator, mapped_block_group_descriptors, total_block_groups) using allocator
		block_group_descriptor_inode_usage_bitmaps = List<link>(allocator, total_block_groups, true) using allocator

		callback = (status: u16, request: BaseRequest<Ext2>) -> {
			if status != 0 {
				debug.write_line('Ext2: Failed to load block group descriptors')
				return
			}

			request.data.process_block_group_descriptors_and_continue()

		} as (u16, BlockDeviceRequest) -> bool

		request = BaseRequest<Ext2>(allocator, block_group_descriptors_physical_address as u64, callback) using allocator
		request.data = this
		request.set_device_region(device, block_group_descriptors_offset, block_groups_memory_size)

		device.read(request)
	}

	private process_block_group_descriptors_and_continue(): _ {
		descriptor = block_group_descriptors[0]
		debug.write_line('Ext2: Block group descriptor: ')
		debug.write('  Block usage bitmap (block address): ') debug.write_line(descriptor.block_usage_bitmap)
		debug.write('  Inode usage bitmap (block address): ') debug.write_line(descriptor.inode_usage_bitmap)
		debug.write('  Inode table (block address): ') debug.write_line(descriptor.inode_table)	
		debug.write('  Number of unallocated blocks: ') debug.write_line(descriptor.unallocated_block_count)
		debug.write('  Number of unallocated inodes: ') debug.write_line(descriptor.unallocated_inode_count)
		debug.write('  Number of directories: ') debug.write_line(descriptor.directory_count)
	}

	load_root_inode(): _ {
		debug.write_line('Ext2: Loading root inode...')
		root_inode = Ext2DirectoryInode(allocator, this, 2, String.empty) using allocator
		load_inode_information(2, root_inode.(Ext2DirectoryInode).information)
	}

	private wait(): _ {
		require(get_process().is_blocked, 'Attempted to wait for io request, but the process was not blocked')
		interrupts.scheduler.yield()
	}

	load_inode_information(inode: u64, information: InodeInformation): u64 {
		# Compute which block groups contains the inode
		# Note: Inodes are 1-based, so we subtract 1 to get the index
		block_group_index = (inode - 1) / superblock.inodes_in_block_group

		# Compute which entry in the inode table contains the information about the inode
		inode_table_index = (inode - 1) % superblock.inodes_in_block_group

		# Compute the byte offset of the inode relative to the inode table
		inode_relative_byte_offset = inode_table_index * superblock.inode_size

		# Compute the block that contains the inode relative to the inode table
		inode_containing_relative_block = inode_relative_byte_offset / block_size

		# Load where the inode table start
		inode_table_start_block = block_group_descriptors[block_group_index].inode_table

		# Compute the real block that contains the inode
		inode_containing_block = inode_table_start_block + inode_containing_relative_block

		# Compute where the block that contains the inode is in bytes
		inode_containing_block_byte_offset = inode_containing_block * block_size

		# Compute where the inode is inside the block
		inode_inside_block_byte_offset = inode_relative_byte_offset % block_size

		debug.write('Ext2: Reading a block containing the inode from byte offset ') debug.write_address(inode_containing_block_byte_offset) debug.write_line()
		debug.write('Ext2: Byte offset of the inode inside the block = ') debug.write_address(inode_inside_block_byte_offset) debug.write_line()

		# Allocate memory for the inode information
		inode_information_device_size = memory.round_to(superblock.inode_size, device.block_size)
		inode_information_physical_address = PhysicalMemoryManager.instance.allocate_physical_region(inode_information_device_size)

		callback = (status: u16, request: BaseRequest<Process>) -> {
			request.status = status

			if status == 0 request.data.unblock()
			else debug.write_line('Ext2: Failed to read inode information')

			return true
		}

		# Add a blocker for the process, so that when this process starts to wait below, it does not get rescheduled before the callback unblocks the process
		process = get_process()
		process.block(Blocker() using KernelHeap)

		request = BaseRequest<Process>(allocator, inode_information_physical_address as u64, callback as (u16, BlockDeviceRequest) -> bool) using allocator
		request.data = process
		request.set_device_region(device, inode_containing_block_byte_offset, block_size)

		debug.write_line('Ext2: Reading inode information...')
		device.read(request)

		# Wait for the request to finish
		wait()

		debug.write_line('Ext2: Finished reading the inode information')

		# Verify we succeeded
		if request.status != 0 return request.status

		# Copy the inode information into the specified data structure
		inode_information = mapper.map_kernel_region(inode_information_physical_address + inode_inside_block_byte_offset, superblock.inode_size)
		memory.copy(information as link, inode_information, sizeof(InodeInformation))

		# Deallocate the physical memory
		PhysicalMemoryManager.instance.deallocate_all(inode_information_physical_address)
		return 0
	}

	# Summary: Attempts to read the specified number of bytes from the specified inode into memory
	read(allocator: Allocator, inode: Inode, size: u64): Result<Segment, u64> {
		# Load information about the inode, so that we can locate its content
		information = InodeInformation()

		result = load_inode_information(inode.index, information)
		if result != 0 return Results.error<Segment, u64>(result)

		# Allocate memory for reading the inode
		data_device_size = memory.round_to(information.size, device.block_size)
		data_physical_address = PhysicalMemoryManager.instance.allocate_physical_region(data_device_size)
		if data_physical_address === none return Results.error<Segment, u64>(ENOMEM)

		# Add a blocker for the process, so that when this process starts to wait below, it does not get rescheduled before the callback unblocks the process
		process = get_process()
		process.block(Blocker() using KernelHeap)

		reader = InodeReader(allocator, process, device, information, data_physical_address, size, block_size, 0) using allocator
		reader.pointers = information.block_pointers
		reader.pointer_count = BLOCK_POINTER_COUNT
		reader.completed = (reader: InodeReader, status: u16) -> {
			# If the completed with an error, report it
			if status != 0 {
				debug.write('Ext2: Reading failed with status ') debug.write_line(status)
				reader.process.unblock()
				return
			}

			read = reader.progress[]
			remaining = reader.size - read

			debug.write('Ext2: Size = ') debug.write(reader.size) debug.write_line(' byte(s)')
			debug.write('Ext2: Progress = ') debug.write(read) debug.write_line(' byte(s)')
			debug.write('Ext2: Remaining = ') debug.write(remaining) debug.write_line(' byte(s)')

			# If we have read all of it, complete the request with success
			if remaining == 0 {
				debug.write_line('Ext2: Reading complete')
				reader.process.unblock()
				return
			}

			# Because the direct block pointers were not enough, start reading the indirect blocks
			if reader.layer < 1 and reader.inode.singly_indirect_block_pointer != 0 {
				debug.write_line('Ext2: Reading singly indirect blocks...')
				reader.end[] = reader.size
				reader.layer = 1
				reader.load(reader.inode.singly_indirect_block_pointer)
			} else reader.layer < 2 and reader.inode.doubly_indirect_block_pointer != 0 {
				debug.write_line('Ext2: Reading doubly indirect blocks...')
				reader.end[] = reader.size
				reader.layer = 2
				reader.load(reader.inode.doubly_indirect_block_pointer)
			} else reader.layer < 3 and reader.inode.triply_indirect_block_pointer != 0 {
				debug.write_line('Ext2: Reading triply indirect blocks...')
				reader.end[] = reader.size
				reader.layer = 3
				reader.load(reader.inode.triply_indirect_block_pointer)
			} else {
				# We read everything we could, so complete the request with success
				reader.process.unblock()
			}
		}

		debug.write_line('Ext2: Reading direct blocks...')
		reader.start()

		# Wait for the request to finish
		wait()

		debug.write_line('Ext2: Finished reading the inode')
		return Results.new<Segment, u64>(Segment.new(data_physical_address, data_physical_address + size))
	}

	# Summary: Produces create options from the specified flags
	get_create_options(flags: u32, is_directory: bool) {
		if not has_flag(flags, O_CREAT) return CREATE_OPTION_NONE

		if is_directory return CREATE_OPTION_DIRECTORY
		return CREATE_OPTION_FILE
	}

	# Summary:
	# Attempts to find the index of the next zero bit in the specified bitmap.
	# If no zero bit is found, -1 is returned.
	private find_zero_bit(bitmap: u8*, size: u32): i64 {
		# Note:
		# We could use 64-bit numbers for faster lookup,
		# but it might be a little bit more complicated and speed should not be an issue here.

		# Find the first byte that contains a zero bit
		byte_index = 0

		loop (byte_index < size, byte_index++) {
			if bitmap[byte_index] != 0xff stop
		}

		if byte_index == size return -1

		# Find the first bit that is zero
		bit_index = 0

		loop (bit_index < 8, bit_index++) {
			if not has_flag(bitmap[byte_index], 1 <| bit_index) stop
		}

		return (byte_index * 8) + bit_index
	}

	# Summary: Returns the next available inode index
	override allocate_inode_index() {
		loop (i = 0, i < block_group_descriptors.size, i++) {
			# Find the first block descriptor group that has an available inodes
			block_group_descriptor = block_group_descriptors[i]
			if block_group_descriptor.unallocated_inode_count == 0 continue

			block_group_descriptor.unallocated_inode_count--

			panic('Todo: Load the inode usage bitmap if needed')

			# Find the first 64-bit value that contains a zero bit
			inode_usage_bitmap = block_group_descriptor_inode_usage_bitmaps[i]
			available_inode_index = find_zero_bit(inode_usage_bitmap, superblock.inodes_in_block_group / 8)
			require(available_inode_index >= 0, 'Failed to find the available inode even though there should be at least one available')

			# Allocate the inode
			inode_byte_index = available_inode_index / 8
			inode_bit_index = available_inode_index % 8
			inode_usage_bitmap[inode_byte_index] |= (1 <| inode_bit_index)

			# Todo: We should write the change to the file system eventually

			return (i * superblock.inodes_in_block_group) + available_inode_index
		}

		panic('Failed to allocate an inode index because there are no available inodes')
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
			if devices.find(metadata.device) has not inode_device {
				return Results.error<OpenFileDescription, u32>(ENXIO)
			}

			description = inode_device.create_file_description(allocator, custody)

		} else {
			# Create the file description using the custody
			description = OpenFileDescription.try_create(allocator, custody)
		}

		local_allocator.deallocate()
		return Results.new<OpenFileDescription, u32>(description)
	}

	# Summary: Attempts to return an iterator that can be used for inspecting the specified directory
	override iterate_directory(allocator: Allocator, inode: Inode) {
		debug.write_line('Ext2: Iterating directory...')
		require(inode.is_directory(), 'Specified inode was not a directory')

		# Attempt to load directory "content" into memory. It will contain the directory entries, but not their data.
		# Todo: Size should be part of metadata, so we do not need to cast below
		data_or_error = read(allocator, inode, inode.(Ext2DirectoryInode).information.size)

		if data_or_error.has_error() {
			debug.write_line('Ext2: Failed to read directory content for iteration')
			return Results.error<DirectoryIterator, u32>(data_or_error.error)
		}

		debug.write_line('Ext2: Finished reading directory entries to memory')

		data_physical_region = data_or_error.value

		# Attempt to allocate a region using the specified allocator where we copy the content
		size = data_physical_region.size
		destination = allocator.allocate(size)

		if destination === none {
			debug.write_line('Ext2: Failed to allocate memory for directory content')
			return Results.error<DirectoryIterator, u32>(ENOMEM)
		}

		# Copy the content into the allocated region
		data = mapper.map_kernel_region(data_physical_region.start, size)
		memory.copy(destination, data, size)

		# Deallocate the physical region
		PhysicalMemoryManager.instance.deallocate_all(data_physical_region.start)

		iterator = Ext2DirectoryIterator(allocator, destination, destination + size) using allocator 
		return Results.new<DirectoryIterator, u32>(iterator)
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