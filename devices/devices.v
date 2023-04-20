namespace kernel.devices

plain Devices {
	private allocator: Allocator
	private devices: Map<u64, Device>

	init(allocator: Allocator) {
		this.allocator = allocator
		this.devices = Map<u64, Device>(allocator) using allocator
	}

	# Summary: Adds the specified device
	add(device: Device): _ {
		devices.add(device.identifier, device)
	}

	# Summary: Attempts to find a device with the specified device identifier
	find(device: u64): Optional<Device> {
		return devices.try_get(device)
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