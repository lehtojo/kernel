namespace kernel.devices.storage

plain BlockDeviceRequest {
	block_index: u64
	block_count: u32
	address: u64
	callback: (u16, BlockDeviceRequest) -> _

	init(block_index: u64, block_count: u64, address: u64, callback: (u16, BlockDeviceRequest) -> _) {
		this.block_index = block_index
		this.block_count = block_count
		this.address = address
		this.callback = callback
	}
}

plain NvmeNamespace {
	namespace_id: u32
	queues: List<NvmeQueue>
	block_count: u64 = 0
	block_size: u32 = 0
	ready: bool = false

	init(namespace_id: u32, queues: List<NvmeQueue>) {
		this.namespace_id = namespace_id
		this.queues = queues
	}

	read(request: BlockDeviceRequest): _ {
		require(request.block_index + request.block_count <= block_count, 'Nvme namespace: Invalid read range')

		queue = queues[Processor.current.index]

		callback = (queue: NvmeQueue, status: u16, userdata: u64) -> {
			request: BlockDeviceRequest = userdata as BlockDeviceRequest
			request.callback((status != 0) as u16, request)
		}

		queue.read(namespace_id, request.block_index, request.block_count, request.address, request as u64, callback)
	}
}