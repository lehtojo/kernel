namespace kernel.file_systems.ext2

import kernel.devices.storage
import kernel.system_calls

constant SUPERBLOCK_OFFSET = 1024

constant FILE_SYSTEM_STATE_CLEAN = 1
constant FILE_SYSTEM_STATE_ERRORS = 2

constant ERROR_HANDLING_METHOD_IGNORE = 1
constant ERROR_HANDLING_METHOD_REMOUNT_READONLY = 2
constant ERROR_HANDLING_METHOD_PANIC = 3

constant OPERATING_SYSTEM_ID = 42

plain Superblock {
	inode_count: u32
	block_count: u32
	superuser_reserved_block_count: u32
	unallocated_block_count: u32
	unallocated_inode_count: u32
	block_containing_superblock: u32
	formatted_block_size: u32 # log2(block_size) - 10
	formatted_fragment_size: u32 # log2(fragment_size) - 10
	blocks_in_block_group: u32
	fragments_in_block_group: u32
	inodes_in_block_group: u32
	last_mount_time: u32
	last_written_time: u32
	mount_count_since_last_consistency_check: u16
	max_allowed_mounts_before_consistency_check: u16
	signature: u16
	file_system_state: u16
	error_handling_method: u16
	minor_version: u16
	last_consistency_check_time: u32
	forced_consistency_check_interval: u32
	creator_operating_system_id: u32
	major_version: u32
	user_id: u16
	group_id: u16
}

# Todo: What is going on with the supertype?
kernel.devices.storage.BlockDeviceRequest Ext2BlockDeviceRequest {
	ext2: Ext2

	init(ext2: Ext2, block_index: u64, block_count: u64, address: u64, callback: (u16, BlockDeviceRequest) -> _) {
		BlockDeviceRequest.init(block_index, block_count, address, callback)
		this.ext2 = ext2
	}
}

Ext2 {
	device: BlockStorageDevice
	superblock: Superblock = none as Superblock

	init(device: BlockStorageDevice) {
		this.device = device
	}

	initialize(): u64 {


	}

	private load_superblock(): _ {
		debug.write_line('Ext2: Loading the superblock...')

		# Compute where the superblock is and how large it is
		superblock_block_index = SUPERBLOCK_OFFSET / device.block_size
		superblock_block_count = memory.round_to(sizeof(Superblock), device.block_size)

		# Allocate memory for loading the superblock
		superblock_physical_address = PhysicalMemoryManager.instance.allocate_physical_region(PAGE_SIZE)
		if superblock_physical_address === none return ENOMEM

		superblock = mapper.map_kernel_page(superblock_physical_address) as Superblock

		callback = (status: u16, request: Ext2BlockDeviceRequest) -> {
			if status != 0 {
				debug.write_line('Ext2: Failed to load the superblock')
				return
			}
	
			superblock: Superblock = request.ext2.superblock

			debug.write_line('Ext2: Superblock: ')
			debug.write('  inode_count: ') debug.write_line(superblock.inode_count)
			debug.write('  block_count: ') debug.write_line(superblock.block_count)
			debug.write('  superuser_reserved_block_count: ') debug.write_line(superblock.superuser_reserved_block_count)
			debug.write('  unallocated_block_count: ') debug.write_line(superblock.unallocated_block_count)
			debug.write('  unallocated_inode_count: ') debug.write_line(superblock.unallocated_inode_count)
			debug.write('  block_containing_superblock: ') debug.write_line(superblock.block_containing_superblock)
			debug.write('  formatted_block_size: ') debug.write_line(superblock.formatted_block_size)
			debug.write('  formatted_fragment_size: ') debug.write_line(superblock.formatted_fragment_size)
			debug.write('  blocks_in_block_group: ') debug.write_line(superblock.blocks_in_block_group)
			debug.write('  fragments_in_block_group: ') debug.write_line(superblock.fragments_in_block_group)
			debug.write('  inodes_in_block_group: ') debug.write_line(superblock.inodes_in_block_group)
			debug.write('  last_mount_time: ') debug.write_line(superblock.last_mount_time)
			debug.write('  last_written_time: ') debug.write_line(superblock.last_written_time)
			debug.write('  mount_count_since_last_consistency_check: ') debug.write_line(superblock.mount_count_since_last_consistency_check)
			debug.write('  max_allowed_mounts_before_consistency_check: ') debug.write_line(superblock.max_allowed_mounts_before_consistency_check)
			debug.write('  signature: ') debug.write_line(superblock.signature)
			debug.write('  file_system_state: ') debug.write_line(superblock.file_system_state)
			debug.write('  error_handling_method: ') debug.write_line(superblock.error_handling_method)
			debug.write('  minor_version: ') debug.write_line(superblock.minor_version)
			debug.write('  last_consistency_check_time: ') debug.write_line(superblock.last_consistency_check_time)
			debug.write('  forced_consistency_check_interval: ') debug.write_line(superblock.forced_consistency_check_interval)
			debug.write('  creator_operating_system_id: ') debug.write_line(superblock.creator_operating_system_id)
			debug.write('  major_version: ') debug.write_line(superblock.major_version)
			debug.write('  user_id: ') debug.write_line(superblock.user_id)
			debug.write('  group_id: ') debug.write_line(superblock.group_id)


		} as (u16, BlockDeviceRequest) -> _

		request = Ext2BlockDeviceRequest(this, superblock_block_index,superblock_block_index, superblock_physical_address as u64, callback) using KernelHeap
		device.read(request)

		return 0
	}
}