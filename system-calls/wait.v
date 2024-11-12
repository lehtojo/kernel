namespace kernel.system_calls

wait_for_any_child_process(process: Process, out_status: u32*, options: u32): u64 {
	childs = process.childs

	# Return immediately if there are no childs to wait for
	if childs.size == 0 {
		debug.write_line('System call: waitpid: No child processes to wait for')
		return ECHILD
	}

	# Block until one of the childs changes state according to the options
	process.block(
		MultiProcessBlocker.try_create(HeapAllocator.instance, childs).then((blocker: MultiProcessBlocker) -> {
			childs: List<Process> = blocker.subscribed

			loop (i = 0, i < childs.size, i++) {
				# Todo: Maybe something should be done about this duplication (wait_for_child_process, vfork)
				child = childs[i]
				if child.state != THREAD_STATE_TERMINATED continue

				# Return the child process pid as the result
				blocker.set_system_call_result(child.pid)
				return true
			}

			return false
		})
	)

	return 0
}

wait_for_child_process(process: Process, pid: u32, out_status: u32*, options: u32): u64 {
	# Attempt to find the process to wait for
	if interrupts.scheduler.find(pid) has not target {
		debug.write('System call: waitpid: Failed to find process with pid of ') debug.write(pid) debug.write_line()
		return ECHILD
	}

	# Block until the target process changes state according to the options
	process.block(
		ProcessBlocker.try_create(HeapAllocator.instance, target).then((blocker: ProcessBlocker) -> {
			target: Process = blocker.subscribed
			if target.state != THREAD_STATE_TERMINATED return false

			# Return the target process pid as the result
			blocker.set_system_call_result(target.pid)
			return true
		})
	)

	return 0
}

# System call: waitpid
export system_waitpid(pid: i32, out_status: u32*, options: u32): u64 {
	debug.write('System call: waitpid: ')
	debug.write('pid=') debug.write(pid)
	debug.write(', out_status=') debug.write_address(out_status)
	debug.write(', options=') debug.write(options)
	debug.write_line()

	process = get_process()

	if pid == -1 return wait_for_any_child_process(process, out_status, options)
	if pid > 0 return wait_for_child_process(process, pid, out_status, options)
	if pid < 0 return wait_for_child_process(process, -pid, out_status, options)

	panic('System call: waitpid: pid == 0 is not supported')
	# return wait_for_any_child_process_in_same_group()	
}