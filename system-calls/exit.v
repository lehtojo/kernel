namespace kernel.system_calls

# System call: exit
export system_exit(frame: TrapFrame*, code: i32) {
	process = interrupts.scheduler.current
	require(process !== none, 'Missing process')

	interrupts.scheduler.exit(frame, process)
}