namespace kernel.devices

plain Devices {
	shared instance: Devices

	private allocator: Allocator
	private devices: Map<u64, Device>

	init(allocator: Allocator) {
		this.allocator = allocator
		this.devices = Map<u64, Device>(allocator) using allocator
	}

	# Summary: Adds the specified device
	add(device: Device): _ {
		debug.write('Devices: Adding device with id ') debug.write_address(device.identifier) debug.write_line()
		devices.add(device.identifier, device)
	}

	# Summary: Attempts to find a device with the specified device identifier
	find(device: u64): Optional<Device> {
		return devices.try_get(device)
	}

	# Summary: Attempts to find a device with the specified major and minor number
	find(major: u64, minor: u64): Optional<Device> {
		identifier = Device.get_identifier(major, minor)
		return find(identifier)
	}

	# Summary: Returns all devices into the specified list
	get_all(devices: List<Device>): _ {
		this.devices.get_values(devices)
	}

	# Summary: Destructs this object
	destruct(): _ {
		devices.destruct(allocator)
		allocator.deallocate(this as link)
	}
}