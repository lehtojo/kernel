namespace kernel.file_systems.ext2

import kernel.devices.storage
import kernel.system_calls

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

		read = progress[]
		data: u32* = mapper.map_kernel_region(address as link, read) as u32*

		loop (i = 0, i < read / sizeof(u32), i++) {
			debug.write_line(data[i])
		}
	}
}

pack ReadRequest {
	caller: Ext2
	request: FileSystemRequest
	inode_inside_block_byte_offset: u32
}

Ext2 {
	constant MIN_SUPPORTED_MAJOR_VERSION = 1

	allocator: Allocator
	device: BlockStorageDevice
	superblock: Superblock = none as Superblock
	block_group_descriptors: List<BlockGroupDescriptor> = none as List<BlockGroupDescriptor>

	block_size => 1 <| (superblock.formatted_block_size + 10)
	fragment_size => 1 <| (superblock.formatted_fragment_size + 10)

	init(allocator: Allocator, device: BlockStorageDevice) {
		this.allocator = allocator
		this.device = device
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

		# Todo: Remove
		destination = PhysicalMemoryManager.instance.allocate_physical_region(PhysicalMemoryManager.L0_SIZE)
		request = FileSystemRequest(15, destination as u64, PhysicalMemoryManager.L0_SIZE) using KernelHeap
		read(request)
	}

	read(request: FileSystemRequest): u64 {
		# Compute which block groups contains the inode
		# Note: Inodes are 1-based, so we subtract 1 to get the index
		block_group_index = (request.inode - 1) / superblock.inodes_in_block_group

		# Compute which entry in the inode table contains the information about the inode
		inode_table_index = (request.inode - 1) % superblock.inodes_in_block_group

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

		callback = (status: u16, request: BaseRequest<ReadRequest>) -> {
			if status == 0 request.data.caller.read(request) 
			else debug.write_line('Ext2: Failed to read inode information')

			return true
		}

		# Read the inode information and then start reading the actual content.
		# Note: We get the content location from the inode information.
		device_request = BaseRequest<ReadRequest>(allocator, inode_information_physical_address as u64, callback as (u16, BlockDeviceRequest) -> bool) using allocator
		device_request.data.caller = this
		device_request.data.request = request
		device_request.data.inode_inside_block_byte_offset = inode_inside_block_byte_offset
		device_request.set_device_region(device, inode_containing_block_byte_offset, block_size)

		debug.write_line('Ext2: Reading inode information...')
		device.read(device_request)
	}

	private read(request: BaseRequest<ReadRequest>): u64 {
		# Map the loaded inode information, so that we can start to read its content
		inode_block = mapper.map_kernel_region(request.physical_address as link, block_size)
		inode = (inode_block + request.data.inode_inside_block_byte_offset) as InodeInformation

		allocator: Allocator = HeapAllocator.instance

		reader = InodeReader(allocator, device, request.data.request, inode, block_size, 0) using allocator
		reader.pointers = inode.block_pointers
		reader.pointer_count = BLOCK_POINTER_COUNT
		reader.completed = (reader: InodeReader, status: u16) -> {
			# If the completed with an error, report it
			if status != 0 {
				debug.write('Ext2: Reading failed with status ') debug.write_line(status)
				reader.request.complete(status)
				return
			}

			read = reader.progress[]
			remaining = reader.request.size - read

			debug.write('Ext2: Size = ') debug.write(reader.request.size) debug.write_line(' byte(s)')
			debug.write('Ext2: Progress = ') debug.write(read) debug.write_line(' byte(s)')
			debug.write('Ext2: Remaining = ') debug.write(remaining) debug.write_line(' byte(s)')

			# If we have read all of it, complete the request with success
			if remaining == 0 {
				debug.write_line('Ext2: Reading complete')
				reader.request.complete(0)
				return
			}

			# Because the direct block pointers were not enough, start reading the indirect blocks
			if reader.layer < 1 and reader.inode.singly_indirect_block_pointer != 0 {
				debug.write_line('Ext2: Reading singly indirect blocks...')
				reader.request.end[] = reader.request.size
				reader.layer = 1
				reader.load(reader.inode.singly_indirect_block_pointer)
			} else reader.layer < 2 and reader.inode.doubly_indirect_block_pointer != 0 {
				debug.write_line('Ext2: Reading doubly indirect blocks...')
				reader.request.end[] = reader.request.size
				reader.layer = 2
				reader.load(reader.inode.doubly_indirect_block_pointer)
			} else reader.layer < 3 and reader.inode.triply_indirect_block_pointer != 0 {
				debug.write_line('Ext2: Reading triply indirect blocks...')
				reader.request.end[] = reader.request.size
				reader.layer = 3
				reader.load(reader.inode.triply_indirect_block_pointer)
			} else {
				# We read everything we could, so complete the request with success
				reader.request.complete(0)
			}
		}

		debug.write_line('Ext2: Reading direct blocks...')
		reader.start()
	}
}