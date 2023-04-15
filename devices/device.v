namespace kernel.devices

import kernel.file_systems

File Device {
	readable major: u32
	readable minor: u32
	readable uid: u32 = 0
	readable gid: u32 = 0

	# Summary: Combines the specified device major and minor numbers into an identifier
	shared get_identifier(major: u32, minor: u32): u64 {
		return (major as u64 <| 32) | minor
	}

	identifier => get_identifier(major, minor)

	init(major: u32, minor: u32) {
		this.major = major
		this.minor = minor
	}

	override is_device() { return true }

	# Summary: Creates an open file description for this device
	create_file_description(allocator: Allocator, custody: Custody): OpenFileDescription {
		panic('Todo: Device file descriptions')
	}
}