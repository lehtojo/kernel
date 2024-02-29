namespace kernel.system_calls

# System call: sched_getaffinity
export system_sched_getaffinity(pid: u32, mask_size: u64, mask: u64*): u64 {
	debug.write('System call: sched_getaffinity: ')
	debug.write('mask_size=') debug.write_address(mask_size)
	debug.write(', mask=') debug.write(mask)
	debug.write_line()

    # Find the process the corresponds to the specified pid
	if interrupts.scheduler.find(pid) has not target {
		debug.write('System call: sched_getaffinity: Failed to find process with pid of ')
        debug.write(pid)
        debug.write_line()
		return ESRCH
	}

    # Verify the kernel affinity mask fits inside the user's mask
    if mask_size < sizeof(u64) {
		debug.write_line('System call: sched_getaffinity: User mask is too small')
        return EINVAL
    }

    # Verify the specified mask is valid
    process = get_process()

	if not is_valid_region(process, mask, mask_size, false) {
		debug.write_line('System call: sched_getaffinity: Invalid mask pointer')
		return EFAULT
	}

    mask[] = target.affinity
	return 0
}