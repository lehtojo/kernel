namespace kernel.file_systems.ext2

import kernel.devices.storage

constant SUPERBLOCK_OFFSET = 1024

constant SIGNATURE = 0xef53

constant FILE_SYSTEM_STATE_CLEAN = 1
constant FILE_SYSTEM_STATE_ERRORS = 2

constant ERROR_HANDLING_METHOD_IGNORE = 1
constant ERROR_HANDLING_METHOD_REMOUNT_READONLY = 2
constant ERROR_HANDLING_METHOD_PANIC = 3

constant OPERATING_SYSTEM_ID = 42

constant BLOCK_POINTER_COUNT = 12

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
	first_unreserved_inode: u32
	inode_size: u16
}

# Todo: What is going on with the supertype?
kernel.devices.storage.BlockDeviceRequest BaseRequest<T> {
	status: u16
	data: T = 0 as T

	init(allocator: Allocator, address: u64, callback: (u16, BlockDeviceRequest) -> bool) {
		BlockDeviceRequest.init(allocator, address, callback)
	}
}

pack BlockGroupDescriptor {
	block_usage_bitmap: u32
	inode_usage_bitmap: u32
	inode_table: u32
	unallocated_block_count: u16
	unallocated_inode_count: u16
	directory_count: u16
	reserved: u8[14]
}

plain InodeInformation {
	type_and_permissions: u16
	user_id: u16
	size_lower: u32
	last_access_time: u32
	creation_time: u32
	last_modification_time: u32
	deletion_time: u32
	group_id: u16
	hard_link_count: u16
	disk_sector_count: u32
	flags: u32
	os_specific_value_1: u32
	block_pointers: u32[BLOCK_POINTER_COUNT]
	singly_indirect_block_pointer: u32
	doubly_indirect_block_pointer: u32
	triply_indirect_block_pointer: u32
	generation_number: u32
	extended_attribute_block: u32
	size_upper: u32
	fragment_block_address: u32
	os_specific_value_2: u8[12]

	size => (size_upper <| 32) | size_lower
}