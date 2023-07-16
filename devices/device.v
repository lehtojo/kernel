namespace kernel.devices

import kernel.file_systems
import kernel.scheduler

File Device {
	readable major: u32
	readable minor: u32
	readable uid: u32 = 0
	readable gid: u32 = 0
	readable subscribers: Subscribers

	inode: InodeIdentifier

	# Summary: Combines the specified device major and minor numbers into an identifier
	shared get_identifier(major: u32, minor: u32): u64 {
		return (major as u64 <| 32) | minor
	}

	identifier => get_identifier(major, minor)

	init(major: u32, minor: u32) {
		this.major = major
		this.minor = minor
		this.subscribers = Subscribers.new(HeapAllocator.instance)
	}

	override is_device() { return true }

	override subscribe(blocker: Blocker) { subscribers.subscribe(blocker) }
	override unsubscribe(blocker: Blocker) { subscribers.unsubscribe(blocker) }

	override load_status(metadata: FileMetadata) {
		debug.write_line('Device: Loading status')

		block_size = 0
		if inode.file_system != 0 { block_size = FileSystems.get(inode.file_system).get_block_size() }

		# Todo: Fill in correct data
		metadata.device_id = inode.file_system
		metadata.inode = inode.inode
		metadata.mode = S_IRWXU | S_IRWXG | S_IRWXO | S_IFCHR
		metadata.hard_link_count = 1
		metadata.uid = 0
		metadata.gid = 0
		metadata.represented_device = identifier
		metadata.size = 0
		metadata.block_size = block_size
		metadata.blocks = 0
		metadata.last_access_time = 0
		metadata.last_modification_time = 0
		metadata.last_change_time = 0
		return 0
	}

	# Summary: Returns the name of this device
	open get_name(): String

	open map(process: Process, region: ProcessMemoryRegion, virtual_address: u64): Optional<i32> { return Optionals.empty<i32>() }

	# Summary: Controls this devices
	open control(request: u32, argument: u64): i32

	# Summary: Creates an open file description for this device
	create_file_description(allocator: Allocator, custody: Custody): OpenFileDescription {
		description = OpenFileDescription.try_create(allocator, this)
		if description === none return none as OpenFileDescription

		description.set_blocking(true) # Todo: Figure out whether the device is actually blocking and maybe this should not even happen here
		return description
	}
}