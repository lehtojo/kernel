namespace kernel.system_calls

# System call: vfork
export system_vfork(): i64 {
	debug.write_line('System call: vfork')

	process = get_process()
	child = process.create_child_with_shared_resources(HeapAllocator.instance)

	# Set the return value from this system call to zero in the child process
	# Todo: Maybe this should be done in a better way?
	child.registers[].rax = 0

	# Register the child process
	interrupts.scheduler.add_process(child)

	# Parent process must wait until the child process is terminated
	# Todo: We also need to consider exec() etc.
	process.block(
		ProcessBlocker.try_create(HeapAllocator.instance, child).then((blocker: ProcessBlocker) -> {
			child: Process = blocker.subscribed

			# We can let the parent process continue once the child process is terminated or no longer uses parent resources (e.g. exec() system call)
			if child.state != THREAD_STATE_TERMINATED and child.is_borrowing_parent_resources return false

			# Return the child process pid as the result
			blocker.set_system_call_result(child.pid)
			return true
		})
	)

	# Todo: Verify exec() in the child process does everything correctly regarding the shared resources

	# Note: Because the caller process is now blocked, the scheduler will pick another process to execute
	return 0
}