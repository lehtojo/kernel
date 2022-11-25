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

	init(allocator: Allocator) {
		this.allocator = allocator
		this.processes = List<Process>(allocator) using allocator
	}

	enter(frame: TrapFrame*, process: Process) {
		
	}

	tick(frame: TrapFrame*) {
		debug.write_line('Scheduler tick')
	}
}