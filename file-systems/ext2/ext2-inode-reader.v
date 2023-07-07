namespace kernel.file_systems.ext2

import kernel.devices.storage
import kernel.system_calls

# Todo: Handle destructing
IndirectBlockOperator InodeReader {
	# Summary: Stores the process that created this reader
	process: Process
	# Summary: Stores the device that will be used to read the inode
	device: BlockStorageDevice
	# Summary: Stores the inode that we are reading
	inode: InodeInformation
	# Summary: Stores the destination address where the data is read
	destination: link
	# Summary: Stores a callback that will be called once we complete with a status
	completed: (InodeReader, u16) -> _ = none as (InodeReader, u16) -> _

	# Todo: This is dumb, nested readers do not need to allocate these as they only use the pointers
	_commited: u64[1]
	_progress: u64[1]
	_end: u64[1]

	init(parent: InodeReader) {
		IndirectBlockOperator.init(parent)
		this.process = parent.process
		this.device = parent.device
		this.inode = parent.inode
		this.destination = parent.destination
		this.completed = parent.completed
	}

	init(allocator: Allocator, process: Process, device: BlockStorageDevice, inode: InodeInformation, destination: link, size: u64, block_size: u32, layer: u8) {
		IndirectBlockOperator.init(allocator, _commited, _progress, _end, block_size, size, layer)
		this.process = process
		this.device = device
		this.inode = inode
		this.destination = destination
	}

	override complete(status: u16) {
		# Tell the most upper operator we have completed the objective
		if parent !== none {
			parent.complete(status)
			return
		}

		if completed !== none completed(this, status)
	}

	load(block: u32): _ {
		# Allocate physical memory for the pointers
		pointers_physical_memory_size = memory.round_to(block_size, device.block_size) 
		pointers_physical_memory = PhysicalMemoryManager.instance.allocate_physical_region(pointers_physical_memory_size)

		if pointers_physical_memory === none {
			fail(ENOMEM)
			return
		}

		# Map the pointers, so that we can access them. Compute the number of them.
		pointers = mapper.map_kernel_region(pointers_physical_memory, pointers_physical_memory_size)
		pointer_index = 0
		pointer_count = block_size / sizeof(u32)

		# Compute where the block is in bytes, which contains the pointers
		read_byte_offset = block * block_size

		callback = (status: u16, request: BaseRequest<InodeReader>) -> {
			reader = request.data

			if status == 0 {
				reader.start() # Start loading the blocks
			} else {
				reader.fail(EIO)
			}

			return true
		}

		request: BaseRequest<InodeReader> = BaseRequest<InodeReader>(allocator, pointers_physical_memory as u64, callback as (u16, BlockDeviceRequest) -> bool) using allocator
		request.data = this
		request.set_device_region(device, read_byte_offset, block_size)

		device.read(request)
	}

	private read_next_indirect_block(block: u32): _ {
		reader = InodeReader(this) using allocator
		reader.load(block)
	}

	# Summary: Reads the specified block
	private read_direct_block(block: u32): _ {
		# Compute where the block is in bytes
		block_byte_offset = block * block_size

		callback = (status: u16, request: BaseRequest<InodeReader>) -> {
			reader = request.data

			if status == 0 {
				reader.progress(reader.block_size) # Report how much we have read
			} else {
				reader.fail(EIO)
			}

			return true
		}

		# Compute where the block should be read
		destination: u64 = (this.destination + commited[]) as u64

		request: BaseRequest<InodeReader> = BaseRequest<InodeReader>(allocator, destination, callback as (u16, BlockDeviceRequest) -> bool) using allocator
		request.data = this
		request.set_device_region(device, block_byte_offset, block_size)

		debug.write('Ext2: Reading block ') debug.write(block) debug.write(' from byte offset ') debug.write_address(block_byte_offset) debug.write_line()
		device.read(request)
	}

	override operate(block: u32) {
		if layer > 1 {
			read_next_indirect_block(block)
			return 0
		}

		read_direct_block(block)
		return block_size # Commited = Number of bytes requested to be read
	}
}