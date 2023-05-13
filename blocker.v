namespace kernel.scheduler

Blocker {
	private callback: (Blocker) -> i64
	process: Process

	# Summary: Sets the callback that is executed when the blocker is unblocked
	then(callback) {
		this.callback = callback as (Blocker) -> i64
		return this
	}

	# Summary: Sets the result of a system call by updating thread registers
	set_system_call_result(result: u64): _ {
		process.registers[].rax = result
	}

	# Summary: Executes the callback and unblocks upon success
	update(): bool {
		require(process !== none, 'Attempted to update unregistered blocker')

		# Execute the callback and save the result
		succeded = callback(this)

		# Do not continue if the callback failed
		if not succeded return false

		unblock()
		process.unblock()
		return true
	}

	open unblock(): _ {}
}

Blocker FileBlocker {
	description: OpenFileDescription
	buffer: link
	size: u64

	shared try_create(allocator: Allocator, description: OpenFileDescription, buffer: link, size: u64): FileBlocker {
		blocker = FileBlocker(allocator, description, buffer, size) using allocator
		description.file.subscribe(blocker)
		return blocker
	}

	private init(allocator: Allocator, description: OpenFileDescription, buffer: link, size: u64) {
		this.description = description
		this.buffer = buffer
		this.size = size
	}

	override unblock() {
		description.file.unsubscribe(this)
	}
}