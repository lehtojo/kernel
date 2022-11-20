namespace kernel.scheduler

Process {
	constant NORMAL_PRIORITY = 50

	id: u64
	priority: u16 = NORMAL_PRIORITY
	registers: RegisterState*

	shared new(allocator: Allocator): Process {
		process = allocator.new<Process>()
		
		return process
	}
}

Scheduler {
	allocator: Allocator
	processes: List<Process>

	shared new(allocator: Allocator): Scheduler {
		scheduler = allocator.new<Scheduler>()
		scheduler.allocator = allocator
		scheduler.processes = Lists.new<Process>(allocator)
		return scheduler
	}

	enter(frame: TrapFrame*, process: Process) {
		
	}

	tick(frame: TrapFrame*) {
		debug.write_line('Scheduler tick')
	}
}