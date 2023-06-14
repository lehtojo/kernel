namespace kernel.devices

Device CharacterDevice {
	init(major: u32, minor: u32) {
		Device.init(major, minor)
	}

	override load_status(metadata: FileMetadata) {
		# Output debug information
		debug.write_line('Character device: Loading status')

		# Todo: Fill in correct data
		metadata.device_id = 1
		metadata.inode = 0
		metadata.mode = S_IRWXU | S_IRWXG | S_IRWXO | S_IFCHR
		metadata.hard_link_count = 1
		metadata.uid = 0
		metadata.gid = 0
		metadata.rdev = identifier
		metadata.size = 0
		metadata.block_size = PAGE_SIZE
		metadata.blocks = 1
		metadata.last_access_time = 0
		metadata.last_modification_time = 0
		metadata.last_change_time = 0
		return 0
	}
}