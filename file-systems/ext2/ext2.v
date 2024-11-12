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

pack ReadRequestData {
	process: Process
	callback: Action<u64>
	destination: u64
	transfer_physical_address: u64
	offset_in_block: u32
	size: u32
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
	shared root_inode: Ext2DirectoryInode

	constant MIN_SUPPORTED_MAJOR_VERSION = 1

	allocator: Allocator
	device: BlockStorageDevice
	superblock: Superblock = none as Superblock
	block_group_descriptors: List<BlockGroupDescriptor> = none as List<BlockGroupDescriptor>
	block_group_descriptor_inode_usage_bitmaps: List<link> = none as List<link>

	block_size => 1 <| (superblock.formatted_block_size + 10)
	fragment_size => 1 <| (superblock.formatted_fragment_size + 10)

	init(allocator: Allocator, device: BlockStorageDevice) {
		this.allocator = allocator
		this.device = device
	}

	initialize(): u64 {
		debug.write_line('Ext2: Initializing...')

		result = load_superblock()

		if result != 0 {
			debug.write_line('Ext2: Failed to load the superblock')
			return result
		}

		result = process_superblock_and_continue()

		if result != 0 {
			debug.write_line('Ext2: Failed to process the superblock')
			return result
		}

		result = process_block_group_descriptors_and_continue()

		if result != 0 {
			debug.write_line('Ext2: Failed to process the block group descriptors')
			return result
		}

		return 0
	}

	private load_superblock(): u64 {
		debug.write_line('Ext2: Loading the superblock...')

		# Allocate memory for loading the superblock
		superblock_device_size = memory.round_to(sizeof(Superblock), device.block_size)
		superblock_physical_address = PhysicalMemoryManager.instance.allocate_physical_region(superblock_device_size)
		if superblock_physical_address === none return ENOMEM

		superblock = mapper.map_kernel_page(superblock_physical_address, MAP_NO_CACHE) as Superblock

		callback = (status: u16, request: BaseRequest<ProgressTracker>) -> {
			request.data.execute(status)
			return true

		} as (u16, BlockDeviceRequest) -> bool
	
		# Add a blocker for the process, so that when this process starts to wait below, it does not get rescheduled before the callback unblocks the process
		process = get_process()
		process.block(Blocker() using KernelHeap)

		tracker = ProgressTracker(process, 1)

		request = BaseRequest<ProgressTracker>(allocator, superblock_physical_address as u64, callback) using allocator
		request.data = tracker
		request.block_index = SUPERBLOCK_OFFSET / device.block_size
		request.set_device_region_size(device, sizeof(Superblock))

		device.read(request)
		wait()

		return tracker.status
	}

	private process_superblock_and_continue(): u64 {
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
		debug.write('  First unreserved inode: ') debug.write_line(superblock.first_unreserved_inode)
		debug.write('  Inode size: ') debug.write_line(superblock.inode_size)
	
		if superblock.signature != SIGNATURE {
			debug.write_line('Ext2: Error: Invalid signature')
			return EIO
		}

		# We do not support versions below 1.0 as some fields are not available such as 64-bit file size
		if superblock.major_version < MIN_SUPPORTED_MAJOR_VERSION {
			debug.write_line('Ext2: Error: Too old file system')
			return EIO
		}

		# Verify the inode size is sensible. If the block size is not multiple of inode sizes,
		# then it might be possible that inode information is across two blocks, which is not supported.
		if not memory.is_aligned(block_size, superblock.inode_size) {
			debug.write_line('Ext2: Error: Block size is not multiple of inode size')
			return EIO
		}

		# Standard requires that inode usage bitmap must fit inside a single block
		if memory.round_to(superblock.inodes_in_block_group, 8) / 8 > block_size {
			debug.write_line('Ext2: Error: Inode usage bitmap does not fit inside a single block')
			return EIO
		}

		return load_block_group_descriptors()
	}

	private load_block_group_descriptors(): u64 {
		debug.write_line('Ext2: Loading block group descriptors...')

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
		mapped_block_group_descriptors = mapper.map_kernel_region(block_group_descriptors_physical_address, block_groups_memory_size, MAP_NO_CACHE)
		block_group_descriptors = List<BlockGroupDescriptor>(allocator, mapped_block_group_descriptors, total_block_groups) using allocator
		block_group_descriptor_inode_usage_bitmaps = List<link>(allocator, total_block_groups, true) using allocator

		callback = (status: u16, request: BaseRequest<ProgressTracker>) -> {
			request.data.execute(status)
			return true

		} as (u16, BlockDeviceRequest) -> bool
	
		# Add a blocker for the process, so that when this process starts to wait below, it does not get rescheduled before the callback unblocks the process
		process = get_process()
		process.block(Blocker() using KernelHeap)

		tracker = ProgressTracker(process, 1)

		request = BaseRequest<ProgressTracker>(allocator, block_group_descriptors_physical_address as u64, callback) using allocator
		request.data = tracker
		request.set_device_region(device, block_group_descriptors_offset, block_groups_memory_size)

		device.read(request)
		wait()

		return tracker.status
	}

	private process_block_group_descriptors_and_continue(): u64 {
		descriptor = block_group_descriptors[0]
		debug.write_line('Ext2: Block group descriptor: ')
		debug.write('  Block usage bitmap (block address): ') debug.write_line(descriptor.block_usage_bitmap)
		debug.write('  Inode usage bitmap (block address): ') debug.write_line(descriptor.inode_usage_bitmap)
		debug.write('  Inode table (block address): ') debug.write_line(descriptor.inode_table)	
		debug.write('  Number of unallocated blocks: ') debug.write_line(descriptor.unallocated_block_count)
		debug.write('  Number of unallocated inodes: ') debug.write_line(descriptor.unallocated_inode_count)
		debug.write('  Number of directories: ') debug.write_line(descriptor.directory_count)

		return load_root_inode()
	}

	private load_root_inode(): u64 {
		debug.write_line('Ext2: Loading root inode...')
		root_inode = Ext2DirectoryInode(allocator, this, 2, String.empty) using allocator
		return load_inode_information(2, root_inode.information)
	}

	wait(): _ {
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

		debug.write('Ext2: Reading information of inode ') debug.write(inode) debug.write_line('...')
		device.read(request)

		# Wait for the request to finish
		wait()

		debug.write_line('Ext2: Finished reading the inode information')

		# Verify we succeeded
		if request.status != 0 return request.status

		# Copy the inode information into the specified data structure
		inode_information = mapper.map_kernel_region(inode_information_physical_address + inode_inside_block_byte_offset, superblock.inode_size, MAP_NO_CACHE)
		memory.copy(information as link, inode_information, sizeof(InodeInformation))

		# Deallocate the physical memory
		PhysicalMemoryManager.instance.deallocate_all(inode_information_physical_address)
		return 0
	}

	# Summary: Reads the specified block with the specified configuration and executes the callback on completion
	read_block(destination: u64, block: u64, offset_in_block: u32, size: u32, callback: Action<u64>): u64 {
		debug.write('Ext2: Reading a block: ')
		debug.write('destination=') debug.write_address(destination)
		debug.write(', block=') debug.write(block)
		debug.write(', offset_in_block=') debug.write(offset_in_block)
		debug.write(', size=') debug.write_line(size)

		require(offset_in_block + size <= block_size, 'Can not read outside the block')

		# Todo: Add block based caching here
		# Todo: Are "holes" (index 0 refers to a block full of zeroes) a real thing?

		# Allocate a physical region for one block
		# Todo: We could have a special function for getting these transfer regions that would control the amount of resources used for transfers. It could yield when we are out of these resources.
		transfer_size = math.max(block_size, device.block_size)
		transfer_physical_address = PhysicalMemoryManager.instance.allocate_physical_region(transfer_size) as u64
		if transfer_physical_address === none return ENOMEM

		# Compute where the block is in bytes
		block_byte_offset = block * block_size

		device_callback = (status: u16, request: BaseRequest<ReadRequestData>) -> {
			data = request.data

			# If we succeeded, copy the wanted region from the transfer region
			if status == 0 {
				# Switch to the process memory, so that we can copy
				data.process.memory.paging_table.use()

				# Copy the wanted region from the transfer region
				transfer = mapper.map_kernel_region((data.transfer_physical_address + data.offset_in_block) as link, data.size, MAP_NO_CACHE)
				memory.copy(data.destination as link, transfer, data.size)

				# Switch back to the original paging table
				interrupts.scheduler.current.memory.paging_table.use()
			} else {
				status = EIO
			}

			# Deallocate the transfer region
			PhysicalMemoryManager.instance.deallocate_all(data.transfer_physical_address as link)

			# Execute the callback now that we have completed the request
			data.callback.execute(status)
			return true
		}

		request = BaseRequest<ReadRequestData>(allocator, transfer_physical_address, device_callback as (u16, BlockDeviceRequest) -> bool) using allocator
		request.data.process = get_process()
		request.data.callback = callback
		request.data.destination = destination
		request.data.transfer_physical_address = transfer_physical_address
		request.data.offset_in_block = offset_in_block
		request.data.size = size
		request.set_device_region(device, block_byte_offset, block_size)

		# Send the request, but do not wait for it to complete
		device.read(request)
		return 0
	}

	# Summary: Reads the specified block with the specified configuration and waits for the data to be read
	read_block(destination: u64, block: u64, offset_in_block: u32, size: u32): u64 {
		process = get_process()

		# Create a progress tracker that will unblock the process after completion
		tracker = ProgressTracker(process, 1)
		result = read_block(destination, block, offset_in_block, size, tracker)
		if result != 0 return result

		# Wait for the read request to complete
		process.block(Blocker() using KernelHeap)
		wait()

		return tracker.status
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

	override get_block_size() {
		return block_size
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

	override access(base: Custody, path: String, mode: u32) {
		debug.write('Ext2: Accessing path ') debug.write_line(path)

		local_allocator = LocalHeapAllocator()
		result = open_path(local_allocator, base, path, CREATE_OPTION_NONE)

		if result.has_error {
			debug.write_line('Ext2: Failed to access the path')
			local_allocator.deallocate()
			return result.error
		}

		debug.write_line('Ext2: Accessed the path successfully')
		local_allocator.deallocate()
		return F_OK
	}

	override lookup_status(base: Custody, path: String, metadata: FileMetadata) {
		debug.write_line('Ext2: Lookup metadata')

		local_allocator = LocalHeapAllocator()

		# Attempt to open the specified path
		open_result = open_path(local_allocator, base, path, CREATE_OPTION_NONE)

		if open_result.has_error {
			debug.write_line('Ext2: Failed to lookup metadata')
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
		metadata.device_major = standard_metadata.represented_device |> 32
		metadata.device_minor = standard_metadata.represented_device & 0xffffffff
		metadata.file_system_device_major = standard_metadata.device_id |> 32
		metadata.file_system_device_minor = standard_metadata.device_id & 0xffffffff
		metadata.mount_id = 0
		return 0
	}

   override read_link(allocator: Allocator, base: Custody, path: String) {
      custody_or_error = open_path(allocator, base, path, CREATE_OPTION_NONE)

      if custody_or_error.has_error {
         debug.write_line('Ext2: Failed to open the specified path')
         return custody_or_error.error
      }

      # Verify we have an inode
      inode = custody_or_error.value.inode
      if inode === none return EINVAL

      # Verify we have a symbolic link
      if not inode.metadata.is_symbolic_link return EINVAL

      return inode.read_link(allocator)
   }

	override open_file(base: Custody, path: String, flags: i32, mode: u32) {
		debug.write('Ext2: Opening file from path ') debug.write_line(path)

		local_allocator = LocalHeapAllocator()

		result = open_path(local_allocator, base, path, get_create_options(flags, false))

		if result.has_error {
			debug.write_line('Ext2: Failed to open the specified path')
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
			if Devices.instance.find(metadata.device) has not inode_device {
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

		# Attempt to allocate a region using the specified allocator where we copy the content
		size = inode.size()
		destination = allocator.allocate(size)

		if destination === none {
			debug.write_line('Ext2: Failed to allocate memory for directory content')
			return Results.error<DirectoryIterator, u32>(ENOMEM)
		}

		# Read the directory entries into the allocated data
		result = inode.read_bytes(destination, 0, size)

		if result != size {
			debug.write_line('Ext2: Failed to read directory content for iteration')

			allocator.deallocate(destination)

			# If no error occurred, but we did not read the correct number of bytes, convert that to error code
			if (result as i64) >= 0 { result = EIO }

			return Results.error<DirectoryIterator, u32>(result)
		}

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

   override load_information(information: FileSystemInformation) {
      debug.write_line('Ext2: Loading file system information')

      information.type = SIGNATURE
      information.block_size = get_block_size()
      information.blocks = superblock.block_count
      information.free_blocks = superblock.unallocated_block_count
      information.free_blocks_unprivileged_user = superblock.unallocated_block_count
      # Todo: Figure out what to with the superuser reserved blocks
      information.inodes = superblock.inode_count
      information.free_inodes = superblock.unallocated_inode_count
      information.file_system_id = id
      information.name_length = 50
      # Todo: Figure out the max name length
      information.fragment_size = fragment_size
      information.flags = 0

      return 0
   }
}
