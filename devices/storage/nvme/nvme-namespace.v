namespace kernel.devices.storage

BlockDeviceRequest {
	allocator: Allocator
	block_index: u64
	block_count: u32
	physical_address: u64
	callback: (u16, BlockDeviceRequest) -> bool

	init(allocator: Allocator, physical_address: u64, callback: (u16, BlockDeviceRequest) -> bool) {
		this.allocator = allocator
		this.block_index = 0
		this.block_count = 0
		this.physical_address = physical_address
		this.callback = callback
	}

	init(allocator: Allocator, block_index: u64, block_count: u64, physical_address: u64, callback: (u16, BlockDeviceRequest) -> bool) {
		this.allocator = allocator
		this.block_index = block_index
		this.block_count = block_count
		this.physical_address = physical_address
		this.callback = callback
	}

	# Summary: Sets the block index based on the device block size
	set_device_region_offset(device: BlockStorageDevice, byte_offset: u64): _ {
		block_size = device.block_size

		require(memory.is_aligned(byte_offset, block_size), 'Byte offset was not multiple of device block size')

		block_index = byte_offset / block_size
	}

	# Summary: Sets the block count based on the device block size
	set_device_region_size(device: BlockStorageDevice, byte_size: u32): _ {
		block_size = device.block_size

		block_count = (byte_size + block_size - 1) / block_size # ceil(byte_size / block_size)
	}

	# Summary: Sets the block index and count based on the device block size
	set_device_region(device: BlockStorageDevice, byte_offset: u64, byte_size: u32): _ {
		set_device_region_offset(device, byte_offset)
		set_device_region_size(device, byte_size)
	}

	destruct(): _ {
		allocator.deallocate(this as link)
	}
}

BlockStorageDevice {
	block_size: u32

	open read(request: BlockDeviceRequest): _
}

BlockStorageDevice NvmeNamespace {
	namespace_id: u32
	queues: List<NvmeQueue>
	block_count: u64 = 0
	ready: bool = false

	init(namespace_id: u32, queues: List<NvmeQueue>) {
		this.namespace_id = namespace_id
		this.queues = queues
	}

	override read(request: BlockDeviceRequest) {
		require(request.block_index + request.block_count <= block_count, 'Nvme namespace: Invalid read range')

		queue = queues[Processor.current.index]

		callback = (queue: NvmeQueue, status: u16, userdata: u64) -> {
			request: BlockDeviceRequest = userdata as BlockDeviceRequest
			terminate = request.callback((status != 0) as u16, request)

			if terminate request.destruct()
		}

		queue.read(namespace_id, request.block_index, request.block_count, request.physical_address, request as u64, callback)
	}
}