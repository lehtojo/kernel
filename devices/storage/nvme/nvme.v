namespace kernel.devices.storage

import kernel.bus
import kernel.acpi
import kernel.system_calls
import kernel.file_systems.ext2

Device Nvme {
	allocator: Allocator
	registers_physical_address: u64
	registers: NvmeRegisters
	capabilities: NvmeCapabilities
	admin_queue: NvmeQueue = none as NvmeQueue
	doorbell_registers: link = none as link
	queues: List<NvmeQueue>
	namespaces: List<NvmeNamespace>
	state: u8 = HOST_STATE_INITIALIZING

	shared try_create(allocator: Allocator, identifier: DeviceIdentifier): Nvme {
		debug.write('Nvme: Attempting to create NVMe device of PCI device ')
		debug.write_line(identifier.address.value)

		# Enable PCI memory space and bus mastering for this device before doing anything
		pci.enable_memory_space(identifier)
		pci.enable_bus_mastering(identifier)

		# Map the device registers so we can configure it
		registers_physical_address: u64 = pci.read_bar(identifier, 0) & pci.BAR_ADDRESS_MASK
		debug.write('Nvme: registers_physical_address=') debug.write_address(registers_physical_address) debug.write_line()

		registers: NvmeRegisters = mapper.map_kernel_region(registers_physical_address as link, sizeof(NvmeRegisters), MAP_NO_CACHE) as NvmeRegisters

		debug.write('Nvme: capabilities=') debug.write_address(registers.capabilities)
		debug.write(', version=') debug.write_address(registers.version) debug.write_line()

		# Verify we support the controller
		if registers.version > MAX_CONTROLLER_VERSION {
			debug.write_line('Nvme: Controller version is too new')
			return none as Nvme
		}

		contoller = Nvme(allocator, identifier, registers_physical_address, registers) using allocator

		# Create an io-queue for each processor
		if contoller.initialize(Processor.count) != 0 return none as Nvme

		return contoller
	}

	init(allocator: Allocator, identifier: DeviceIdentifier, registers_physical_address: u64, registers: NvmeRegisters) {
		Device.init(identifier)
		this.allocator = allocator
		this.registers_physical_address = registers_physical_address
		this.registers = registers
		this.queues = List<NvmeQueue>(allocator) using allocator
		this.namespaces = List<NvmeNamespace>(allocator) using allocator
	}

	private initialize(queue_count: u32): u32 {
		load_capabilities()

		result = reset_controller()
		if result != 0 return result

		map_doorbell_registers(queue_count)

		result = create_admin_queues()
		if result != 0 return result

		result = start_controller()
		if result != 0 return result

		debug.write('Nvme: Creating ') debug.write(queue_count) debug.write_line(' io-queue(s)...')

		loop (i = 0, i < queue_count, i++) {
			create_io_queue()
		}
	}

	# Summary: Loads the capabilities from the controller registers into a more usable format
	private load_capabilities(): _ {
		debug.write_line('Nvme: Loading capabilities...')

		capabilities_value = registers.capabilities

		capabilities.max_host_page = 1 <| (12 + ((capabilities_value |> 52) & 0b1111)) # 2 ^ (12 + MPSMAX)
		capabilities.min_host_page = 1 <| (12 + ((capabilities_value |> 48) & 0b1111)) # 2 ^ (12 + MPSMIN)
		capabilities.supported_command_sets = (capabilities_value |> 37) & 0xff
		capabilities.doorbell_stride = 1 <| (2 + ((capabilities_value |> 32) & 0b1111)) # 2 ^ (2 + DSTRD)
		capabilities.ready_timeout = ((capabilities_value |> 24) & 0xff) * 500 # Note: Stored timeout is in 500 ms units
		capabilities.queue_size = (capabilities_value & 0xffff) + 1 # Note: Queue size is zero based (value of 0 means 1 queue entry)

		admin_submission_queue_size = registers.admin_queue_attributes & 0xfff
		admin_completion_queue_size = (registers.admin_queue_attributes |> 16) & 0xfff
		capabilities.admin_queue_size = math.min(admin_submission_queue_size, admin_completion_queue_size) + 1 # Note: Queue size is zero based

		# Output debug information
		debug.write('Nvme: max_host_page=') debug.write(capabilities.max_host_page)
		debug.write(', min_host_page=') debug.write(capabilities.min_host_page)
		debug.write(', supported_command_sets=') debug.write_address(capabilities.supported_command_sets)
		debug.write(', doorbell_stride=') debug.write(capabilities.doorbell_stride)
		debug.write(', ready_timeout=') debug.write(capabilities.ready_timeout)
		debug.write(', queue_size=') debug.write(capabilities.queue_size)
		debug.write_line()
	}

	# Summary: Waits until the controller ready bit matches the specified ready state. Timeout is used.
	private wait_for_ready(expected_ready: bool): bool {
		timeout_milliseconds = capabilities.ready_timeout

		loop (i = 0, i < timeout_milliseconds, i++) {
			ready = (registers.status & STATUS_READY_BIT) != 0
			if ready == expected_ready return true

			wait_for_millisecond()
		}

		debug.write_line('Nvme: Ready timeout exceeded!')
		return false
	}

	# Summary: Attempts to disable the controller
	private reset_controller(): u32 {
		debug.write_line('Nvme: Resetting controller...')

		if (registers.configuration & CONFIGURATION_ENABLED_BIT) != 0 {
			# Contoller is already enabled, wait until it becomes ready
			if not wait_for_ready(true) return ETIMEOUT 
		}

		# Disable the enabled bit
		registers.configuration &= (!CONFIGURATION_ENABLED_BIT)
		full_memory_barrier()

		# Wait until the contoller becomes unready
		if not wait_for_ready(false) return ETIMEOUT

		return 0
	}

	# Summary: Maps the controller doorbell registers to memory, which are used to notify the controller about queue changes
	private map_doorbell_registers(queue_count: u32): _ {
		debug.write_line('Nvme: Mapping doorbell registers...')

		# Doorbell registers are used to notify the controller (about changes related to queues).
		# Submission queue X tail doorbell = 0x1000+(2X)*Y
		# Completion queue X head doorbell = 0x1000+(2X+1)*Y
		# Y is the doorbell stride
		last_doorbell_offset = (2 * (queue_count - 1) + 1) * capabilities.doorbell_stride
		doorbell_registers_size = last_doorbell_offset + capabilities.doorbell_stride
		debug.write('Nvme: Doorbell registers require ') debug.write(doorbell_registers_size) debug.write_line(' byte(s)')

		doorbell_registers = mapper.map_kernel_region((registers_physical_address + DOORBELL_REGISTERS_OFFSET) as link, doorbell_registers_size, MAP_NO_CACHE)
		debug.write('Nvme: doorbell_registers=') debug.write_address(doorbell_registers) debug.write_line()
	}

	# Summary: Creates the admin submission and completion queues, which are used for initialization and creating io-queues
	private create_admin_queues(): u32 {
		debug.write_line('Nvme: Creating admin queues...')

		# Allocate admin submission and completion queues and zero out the memory
		admin_submission_queue_size = SUBMISSION_QUEUE_ENTRY_SIZE * capabilities.admin_queue_size
		admin_completion_queue_size = COMPLETION_QUEUE_ENTRY_SIZE * capabilities.admin_queue_size
		admin_submission_queue_physical_address = PhysicalMemoryManager.instance.allocate_physical_region(admin_submission_queue_size)
		admin_completion_queue_physical_address = PhysicalMemoryManager.instance.allocate_physical_region(admin_completion_queue_size)
		if admin_submission_queue_physical_address === none or admin_completion_queue_physical_address == none return ENOMEM

		admin_submission_queue = mapper.map_kernel_region(admin_submission_queue_physical_address, admin_submission_queue_size, MAP_NO_CACHE)
		admin_completion_queue = mapper.map_kernel_region(admin_completion_queue_physical_address, admin_completion_queue_size, MAP_NO_CACHE)

		debug.write_line('Nvme: Zeroing admin queue regions...')
		memory.zero(admin_submission_queue, admin_submission_queue_size)
		memory.zero(admin_completion_queue, admin_completion_queue_size)

		# Tell the controller where the queues are located
		debug.write_line('Nvme: Registering admin queues...')
		registers.admin_submission_queue = admin_submission_queue_physical_address as u64
		registers.admin_completion_queue = admin_completion_queue_physical_address as u64

		# Compute the doorbell registers:
		admin_submission_queue_doorbell = doorbell_registers as u32*
		admin_completion_queue_doorbell = (doorbell_registers + capabilities.doorbell_stride) as u32*

		# Allocate the memory region used for transferring data to/from the controller
		# Todo: The same problem with the region size as below and do admin queues need data transfer region?
		data_transfer_region = PhysicalMemoryManager.instance.allocate_physical_region(PAGE_SIZE)

		if data_transfer_region === none {
			debug.write_line('Nvme: Failed to allocate data transfer region for admin queues')

			PhysicalMemoryManager.instance.deallocate_all(admin_submission_queue_physical_address)
			PhysicalMemoryManager.instance.deallocate_all(admin_completion_queue_physical_address)
			return ENOMEM
		}

		admin_queue_interrupt = allocate_interrupt(0) # Admin queues use interrupt vector 0 (MSI-X)

		admin_queue = NvmeQueue(
			allocator,
			this,
			admin_submission_queue,
			admin_completion_queue,
			admin_submission_queue_doorbell,
			admin_completion_queue_doorbell,
			data_transfer_region,
			capabilities.admin_queue_size,
			0,
			admin_queue_interrupt
		) using allocator

		return 0
	}

	# Summary: Starts the controller
	private start_controller(): u32 {
		debug.write_line('Nvme: Starting controller...')
		require((registers.configuration & CONFIGURATION_ENABLED_BIT) == 0, 'Nvme: Attempted to start controller while it was enabled')

		# Enable the controller and configure the queue entry sizes as well
		configuration = registers.configuration
		configuration |= CONFIGURATION_ENABLED_BIT
		configuration |= (SUBMISSION_QUEUE_ENTRY_SIZE_EXPONENT <| 16)
		configuration |= (COMPLETION_QUEUE_ENTRY_SIZE_EXPONENT <| 20)
		registers.configuration = configuration
		full_memory_barrier()

		# Wait until the contoller becomes ready
		if not wait_for_ready(true) return ETIMEOUT

		return 0
	}

	# Summary: Creates an io-queue, which is used for reading and writing data for example
	private create_io_queue(): _ {
		debug.write_line('Nvme: Creating an io-queue...')
		create_io_queue_completion_queue(queues.size + 1)
	}

	# Summary: Creates a completion queue for the specified io-queue. After that submission queue is created.
	private create_io_queue_completion_queue(queue_index: u32): _ {
		debug.write_line('Nvme: Creating completion queue for io-queue...')
	
		completion_queue_size = SUBMISSION_QUEUE_ENTRY_SIZE * IO_QUEUE_SIZE
		completion_queue_physical_address = PhysicalMemoryManager.instance.allocate_physical_region(completion_queue_size)

		if completion_queue_physical_address === none {
			debug.write_line('Nvme: Failed to allocate physical memory for completion queue')
			return
		}

		debug.write_line('Nvme: Zeroing out completion queue...')
		completion_queue = mapper.map_kernel_region(completion_queue_physical_address, completion_queue_size, MAP_NO_CACHE)
		memory.zero(completion_queue, completion_queue_size)

		# Create a queue that is not ready that will be initialized during multiple submissions
		queue = NvmeQueue(HeapAllocator.instance, this, IO_QUEUE_SIZE, queue_index) using KernelHeap
		queue.completion_queue = completion_queue as NvmeCompletion*
		queues.add(queue)

		submission = NvmeCreateCompletionQueueCommand()
		memory.zero(submission as link, sizeof(NvmeCreateCompletionQueueCommand))
		submission.header.operation = OPERATION_ADMIN_CREATE_COMPLETION_QUEUE
		submission.header.command_id = admin_queue.next_command_id()
		submission.physical_region_page = completion_queue_physical_address as u64
		submission.completion_queue_id = queue_index
		submission.queue_size = IO_QUEUE_SIZE - 1
		submission.completion_queue_flags = QUEUE_INTERRUPT_ENABLED | QUEUE_PHYSICALLY_CONTIGUOUS
		submission.interrupt_vector = queue_index

		admin_queue.submit(submission as NvmeSubmission*, queue as u64, (admin_queue: NvmeQueue, status: u16, data: u64) -> {
			queue = data as NvmeQueue

			# Verify the command succeeded
			if status != 0 {
				debug.write_line('Nvme: Failed to create completion queue')
				deallocate_queue(queue)
				return
			}

			create_io_queue_submission_queue(admin_queue, queue)
		})
	}

	# Summary: Creates a submission queue for the specified io-queue. After that the io-queue initialization is finished.
	private shared create_io_queue_submission_queue(admin_queue: NvmeQueue, queue: NvmeQueue): _ {
		debug.write_line('Nvme: Creating submission queue for io-queue...')

		submission_queue_size = SUBMISSION_QUEUE_ENTRY_SIZE * IO_QUEUE_SIZE
		submission_queue_physical_address = PhysicalMemoryManager.instance.allocate_physical_region(submission_queue_size)

		if submission_queue_physical_address === none {
			debug.write_line('Nvme: Failed to allocate submission queue physical region')

			deallocate_queue(queue)
			return
		}

		debug.write_line('Nvme: Zeroing out submission queue...')
		submission_queue = mapper.map_kernel_region(submission_queue_physical_address, submission_queue_size, MAP_NO_CACHE)
		memory.zero(submission_queue, submission_queue_size)

		# Store the created submission queue
		queue.submission_queue = submission_queue as NvmeSubmission*

		submission = NvmeCreateSubmissionQueueCommand()
		memory.zero(submission as link, sizeof(NvmeCreateSubmissionQueueCommand))
		submission.header.operation = OPERATION_ADMIN_CREATE_SUBMISSION_QUEUE
		submission.header.command_id = admin_queue.next_command_id()
		submission.physical_region_page = submission_queue_physical_address as u64
		submission.submission_queue_id = queue.queue_index
		submission.queue_size = IO_QUEUE_SIZE - 1
		submission.submission_queue_flags = QUEUE_PHYSICALLY_CONTIGUOUS
		submission.completion_queue_id = queue.queue_index

		admin_queue.submit(submission as NvmeSubmission*, queue as u64, (admin_queue: NvmeQueue, status: u16, data: u64) -> {
			queue = data as NvmeQueue

			# Verify the command succeeded
			if status != 0 {
				debug.write_line('Nvme: Failed to create submission queue')
				deallocate_queue(queue)
				return
			}

			finish_queue_initialization(admin_queue, queue)
		})
	}

	# Summary: Finishes the initialization of the specified io-queue
	private shared finish_queue_initialization(admin_queue: NvmeQueue, queue: NvmeQueue): _ {
		debug.write_line('Nvme: Finishing io-queue initialization...')

		# Allocate the memory region used for transferring data to/from the controller
		# Todo: This seems to be the region used for transferring data, the size should be decided based on the capabilities, since it could be larger than 4K
		data_transfer_region = PhysicalMemoryManager.instance.allocate_physical_region(PAGE_SIZE)

		if data_transfer_region === none {
			debug.write_line('Nvme: Failed to allocate the data transfer region')

			deallocate_queue(queue)
			return
		}

		# Compute the doorbell registers:
		# Submission queue X tail doorbell = 0x1000+(2X)*Y
		# Completion queue X head doorbell = 0x1000+(2X+1)*Y
		controller = admin_queue.controller
		submission_queue_doorbell = (controller.doorbell_registers + (2 * queue.queue_index) * controller.capabilities.doorbell_stride) as u32*
		completion_queue_doorbell = (submission_queue_doorbell + controller.capabilities.doorbell_stride) as u32*

		queue.submission_queue_doorbell = submission_queue_doorbell
		queue.completion_queue_doorbell = completion_queue_doorbell
		queue.data_transfer_region = data_transfer_region
		queue.interrupt = controller.allocate_interrupt(queue.queue_index)
		queue.ready = true

		debug.write_line('Nvme: Successfully created the io-queue')
	}

	# Summary: Deallocates all resources of the specified queue
	private shared deallocate_queue(queue: NvmeQueue): _ {
		# Todo: We should deallocate the resources from the controller?

		if queue.submission_queue !== none {
			PhysicalMemoryManager.instance.deallocate_all(queue.submission_queue)
		}

		if queue.completion_queue !== none {
			PhysicalMemoryManager.instance.deallocate_all(queue.completion_queue)
		}
	}

	# Summary: Identifies all namespaces from the controller and load information about them
	private identify(): _ {
		debug.write_line('Nvme: Identifying active namespaces...')
		identify_data_physical_address = PhysicalMemoryManager.instance.allocate_physical_region(PAGE_SIZE)

		identify_data = mapper.map_kernel_page(identify_data_physical_address as link, MAP_NO_CACHE) as u32*
		memory.zero(identify_data as link, PAGE_SIZE)

		submission = NvmeIdentifyCommand()
		memory.zero(submission as link, sizeof(NvmeIdentifyCommand))
		submission.header.operation = OPERATION_ADMIN_IDENTIFY
		submission.header.command_id = admin_queue.next_command_id()
		submission.data_pointer.physical_region_page_1 = identify_data_physical_address as u64
		submission.controller_namespace = CONTOLLER_NAMESPACE_ACTIVE

		admin_queue.submit(submission as NvmeSubmission*, identify_data as u64, (admin_queue: NvmeQueue, status: u16, identify_data_address: u64) -> {
			if status == 0 {
				controller = admin_queue.controller
				active_namespaces = identify_data_address as u32*

				# Compute the number of active namespaces and add empty namespaces to the list
				active_namespace_count = 0

				loop (active_namespace_count < MAX_IDENTIFY_NAMESPACE_COUNT, active_namespace_count++) {
					# Once we find active namespace of zero, we have reached the end of active namespaces
					active_namespace = active_namespaces[active_namespace_count]
					if active_namespace == 0 stop

					controller.namespaces.add(NvmeNamespace(active_namespace, controller.queues) using KernelHeap)
				}

				controller.state = HOST_STATE_LOADING_NAMESPACE_INFORMATION

				# Load information about the namespaces
				loop (i = 0, i < active_namespace_count, i++) {
					controller.load_namespace_information(controller.namespaces[i])
				}
			} else {
				debug.write_line('Nvme: Failed to identify active namespaces')
			}

			# Now that all active namespaces have been iterated, deallocate the identify data
			KernelHeap.deallocate(identify_data_address as link)
		})
	}

	# Summary: Loads information about the specified namespace
	private load_namespace_information(active_namespace: NvmeNamespace): _ {
		debug.write('Nvme: Identifying active namespace ') debug.write_line(active_namespace.namespace_id)
		identify_data_physical_address = PhysicalMemoryManager.instance.allocate_physical_region(PAGE_SIZE)

		identify_data = mapper.map_kernel_page(identify_data_physical_address as link, MAP_NO_CACHE) as NvmeIdentifyNamespace
		memory.zero(identify_data as link, sizeof(NvmeIdentifyNamespace))

		submission = NvmeIdentifyCommand()
		memory.zero(submission as link, sizeof(NvmeIdentifyCommand))
		submission.header.operation = OPERATION_ADMIN_IDENTIFY
		submission.header.command_id = admin_queue.next_command_id()
		submission.data_pointer.physical_region_page_1 = identify_data_physical_address as u64
		submission.controller_namespace = CONTOLLER_NAMESPACE_ID
		submission.namespace_id = active_namespace.namespace_id

		userdata = NvmeIdentifyNamespaceRequestUserdata(
			identify_data_physical_address,
			identify_data as NvmeIdentifyNamespace,
			active_namespace
		) using KernelHeap

		admin_queue.submit(submission as NvmeSubmission*, userdata as u64, (admin_queue: NvmeQueue, status: u16, userdata_address: u64) -> {
			userdata: NvmeIdentifyNamespaceRequestUserdata = userdata_address as NvmeIdentifyNamespaceRequestUserdata

			if status == 0 {
				contoller = admin_queue.controller

				identify_data = userdata.identify_data

				formatted_lba_size = (identify_data.formatted_lba_size & LBA_FORMAT_SIZE_MASK)
				lba_format = identify_data.lba_formats[formatted_lba_size]
				lba_size = (lba_format & LBA_SIZE_MASK) |> 16

				block_count = identify_data.namespace_size
				block_size = 1 <| lba_size # 2 ^ lba_size

				debug.write('Nvme: Namespace: Number of blocks: ') debug.write(block_count)
				debug.write(', Block size: ') debug.write_line(block_size)

				userdata.active_namespace.block_count = block_count
				userdata.active_namespace.block_size = block_size
				userdata.active_namespace.ready = true

			} else {
				debug.write_line('Nvme: Failed to identify active namespace')
			}

			# Deallocate the identify data, because it is processed
			PhysicalMemoryManager.instance.deallocate_all(userdata.identify_data_physical_address)
			KernelHeap.deallocate(userdata as link)
		})
	}

	# Summary: Handles the initialization states of this controller
	private handle_state(): _ {
		if state == HOST_STATE_INITIALIZING {
			# Wait until all io-queues are created
			if queues.size < 1 return

			# Identify namespaces from the controller
			state = HOST_STATE_IDENTIFYING
			identify()
			return
		}

		if state == HOST_STATE_LOADING_NAMESPACE_INFORMATION {
			# Require all namespaces to be ready before stating that we are complete
			loop (i = 0, i < namespaces.size, i++) {
				if not namespaces[i].ready return
			}			

			debug.write_line('Nvme: All done')
			state = HOST_STATE_COMPLETE # All done

			ext2 = Ext2(HeapAllocator.instance, namespaces[0]) using KernelHeap
			Ext2.instance = ext2

			FileSystems.add(ext2)
			return
		}
	}

	# Summary: Processes queue updates
	override interrupt(interrupt: u8, frame: RegisterState*) {
		if admin_queue.interrupt == interrupt {
			admin_queue.process_completion_queue()
			handle_state()
			return 0
		}

		loop (i = 0, i < queues.size, i++) {
			queue = queues[i]
			if queue.interrupt != interrupt continue

			queue.process_completion_queue() 
		}

		return 0
	}
}