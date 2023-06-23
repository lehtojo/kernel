namespace kernel.devices.storage

pack NvmeQueueRequest {
	callback: (NvmeQueue, u16, u64) -> _
	data: u64

	shared new(callback: (NvmeQueue, u16, u64) -> _, data: u64): NvmeQueueRequest {
		return pack { callback: callback, data: data } as NvmeQueueRequest
	}
}

plain NvmeQueue {
	readable allocator: Allocator
	readable controller: Nvme
	readable queue_size: u32
	readable queue_index: u16
	readable submission_queue_tail: u32 = 0
	readable completion_queue_head: u32 = 0
	readable completion_queue_phase: u16 = 1

	submission_queue: NvmeSubmission*
	completion_queue: NvmeCompletion*
	submission_queue_doorbell: u32*
	completion_queue_doorbell: u32*
	data_transfer_region: link
	interrupt: u8
	ready: bool

	private requests: Map<u16, NvmeQueueRequest>
	private next_available_command_id: u16 = 0

	init(allocator: Allocator, controller: Nvme, queue_size: u32, queue_index: u16) {
		this.requests = Map<u16, NvmeQueueRequest>(allocator) using allocator
		this.allocator = allocator
		this.controller = controller
		this.submission_queue = none as NvmeSubmission*
		this.completion_queue = none as NvmeCompletion*
		this.submission_queue_doorbell = none as u32*
		this.completion_queue_doorbell = none as u32*
		this.data_transfer_region = none as link
		this.queue_size = queue_size
		this.queue_index = queue_index
		this.interrupt = 0
		this.ready = false
	}

	init(
		allocator: Allocator, controller: Nvme,
		submission_queue: NvmeSubmission*, completion_queue: NvmeCompletion*,
		submission_queue_doorbell: u32*, completion_queue_doorbell: u32*,
		data_transfer_region: link,
		queue_size: u32, queue_index: u16, interrupt: u8
	) {
		this.requests = Map<u16, NvmeQueueRequest>(allocator) using allocator
		this.allocator = allocator
		this.controller = controller
		this.submission_queue = submission_queue
		this.completion_queue = completion_queue
		this.submission_queue_doorbell = submission_queue_doorbell
		this.completion_queue_doorbell = completion_queue_doorbell
		this.data_transfer_region = data_transfer_region
		this.queue_size = queue_size
		this.queue_index = queue_index
		this.interrupt = interrupt
		this.ready = true
	}

	# Summary: Tells the controller where the head of the submission queue is
	private update_submission_queue_doorbell(): _ {
		submission_queue_doorbell[] = submission_queue_tail
	}

	# Summary: Tells the controller where the head of the completion queue is
	private update_completion_queue_doorbell(): _ {
		completion_queue_doorbell[] = completion_queue_head
	}

	# Summary: Tells whether the completion queue has a new entry available
	private is_completion_queue_entry_available(): bool {
		# We have a new completion queue entry when the phase bit matches the next expected value.
		# Basically the phase bit switches between 0 and 1 when the queue loops back to the beginning.
		phase = completion_queue[completion_queue_head].status & 1
		return phase == completion_queue_phase
	}

	private update_submission_queue_tail(): _ {
		next_tail = submission_queue_tail + 1

		if next_tail == queue_size {
			# Loop back to the beginning
			submission_queue_tail = 0
		} else {
			submission_queue_tail = next_tail
		}	
	}

	private update_completion_queue_head(): _ {
		next_head = completion_queue_head + 1

		if next_head == queue_size {
			# Loop back to the beginning and switch the phase bit
			completion_queue_head = 0
			completion_queue_phase ¤= 1
		} else {
			completion_queue_head = next_head
		}
	}

	process_completion_queue(): u32 {
		debug.write_line('Nvme queue: Processing completion queue...')
		processed = 0

		loop (is_completion_queue_entry_available()) {
			processed++

			status = completion_queue[completion_queue_head].status |> 1
			command_id = completion_queue[completion_queue_head].command_id

			debug.write('Nvme queue: Completion with status ') debug.write_address(status)
			debug.write(' and command id ') debug.write_line(command_id)

			if requests.contains_key(command_id) {
				complete_request(command_id, status)			
			} else {
				debug.write_line('ERROR: Nvme: Received completion, but the completed request does not exist')
			}

			update_completion_queue_head() # Update where the next entry in the completion queue is
		}

		# If we processed something, report it to the controller
		if processed > 0 update_completion_queue_doorbell()

		return processed
	}

	private complete_request(command_id: u16, status: u8): _ {
		request = requests[command_id]

		# Call the callback with the specified data
		request.callback(this, status, request.data)

		# Remove the request from the map
		requests.remove(command_id)
	}

	read(namespace_id: u32, block_index: u64, block_count: u32, destination: u64, userdata: u64, callback: (NvmeQueue, u16, u64) -> _): _ {
		zero_based_block_count = (block_count - 1) & 0xffff
		require(zero_based_block_count <= 0xffff, 'Invalid block count')

		submission = NvmeReadWriteCommand()
		memory.zero(submission as link, sizeof(NvmeReadWriteCommand))
		submission.header.operation = OPERATION_NVME_READ
		submission.header.command_id = next_command_id()
		submission.namespace_id = namespace_id
		submission.slba = block_index
		submission.length = zero_based_block_count
		submission.data_pointer.physical_region_page_1 = destination

		submit(submission as NvmeSubmission*, userdata, callback)
	}

	next_command_id(): u16 {
		return ++next_available_command_id
	}

	submit(submission: NvmeSubmission*, data: u64, callback: (NvmeQueue, u16, u64) -> _): _ {
		debug.write_line('Nvme queue: Submitting command')
		require(not requests.contains_key(submission[].header.command_id), 'Nvme: Request with the same command id already exists')

		# Register the request, so that it will be handled
		requests[submission[].header.command_id] = NvmeQueueRequest.new(callback, data)

		# Copy the specified submission to the end of the submission queue
		memory.copy(submission_queue + submission_queue_tail * sizeof(NvmeSubmission), submission, sizeof(NvmeSubmission))

		# Update where the next entry in the submission queue is
		update_submission_queue_tail()
		full_memory_barrier()

		# Report the submission to the controller
		update_submission_queue_doorbell()
	}
}