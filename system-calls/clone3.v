namespace kernel.system_calls

write_tids(arguments: CloneArguments, parent: Process, child: Process): i64 {
	child_tid = arguments.child_tid as u32*
	parent_tid = arguments.parent_tid as u32*
	flags = arguments.flags

	# Todo: Handle these differently we support cloning with CLONE_STOPPED
	# Todo: Maybe replace is_valid_region with something more readable?
	if has_flag(flags, CLONE_CHILD_SETTID) {
		if not is_valid_region(parent, child_tid, sizeof(u32), true) return EINVAL
		child_tid[] = child.tid
	}

	if has_flag(flags, CLONE_PARENT_SETTID) {
		if not is_valid_region(parent, parent_tid, sizeof(u32), true) return EINVAL
		parent_tid[] = parent.tid
	}

	return 0
}

# System call: clone3
export system_clone3(arguments_pointer: u64, size: u64): i64 {
	debug.write('System call: clone3: ')
	debug.write('arguments=') debug.write_address(arguments_pointer)
	debug.write(', size=') debug.write(size)
	debug.write_line()

	process = get_process()

	# Verify the arguments structure
	if size < sizeof(CloneArguments) return EINVAL

	arguments = arguments_pointer as CloneArguments

	process_or_error = process.clone(HeapAllocator.instance, arguments)

	if process_or_error has not created_process {
		debug.write_line('System call: clone3: Failed to clone the process')
		return process_or_error.error
	}

	# Register the created thread or process
	if has_flag(arguments.flags, CLONE_NEWPID) {
		interrupts.scheduler.add_process(created_process)
	} else {
		interrupts.scheduler.add_thread(created_process)
	}

	# Write parent and child TIDs if the caller requests them
	write_tids(arguments, process, created_process)

	# Return zero to the child process
	created_process.registers[].rax = 0

	# Return the child tid to the caller process
	return created_process.tid
}