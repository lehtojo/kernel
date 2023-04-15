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

	# Summary: Attempts to find a device with the specified identifier numbers
	find(major: u32, minor: u32): Optional<Device> {
		return devices.try_get(Device.get_identifier(major, minor))
	}

	# Summary: Destructs this object
	destruct(): _ {
		devices.destruct(allocator)
		allocator.deallocate(this as link)
	}
}