namespace kernel.system_calls

# System call: exit
export system_exit(frame: TrapFrame*, code: i32) {
	interrupts.scheduler.exit(frame, get_process())
}