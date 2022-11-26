namespace kernel.scheduler

namespace internal {
	import 'C' scheduler_start(registers: RegisterState*)
}

Process {
	constant NORMAL_PRIORITY = 50

	id: u64
	priority: u16 = NORMAL_PRIORITY
	registers: RegisterState*

	init(id: u64, registers: RegisterState*) {
		this.id = id
		this.registers = registers
	}

	save(frame: TrapFrame*) {
		registers[] = frame[].registers[]
	}
}

Scheduler {
	allocator: Allocator
	current: Process
	processes: List<Process>

	init(allocator: Allocator) {
		this.allocator = allocator
		this.processes = List<Process>(allocator, 256, false) using allocator
	}

	add(process: Process) {
		processes.add(process)
	}

	pick(): Process {
		return processes[0]
	}

	switch(frame: TrapFrame*, next: Process) {
		debug.write('Switching to process ')
		debug.write(next.id)
		debug.write_line()

		frame[].registers[] = next.registers[]

		current = next
	}

	enter(frame: TrapFrame*, next: Process) {
		debug.write('Entering to process ')
		debug.write_line(next.id)

		if current !== next switch(frame, next)
	}

	tick(frame: TrapFrame*) {
		debug.write('Scheduler tick: ')

		# Save the state of the current process
		if current !== none {
			current.save(frame)

			debug.write('rip=')
			debug.write_address(current.registers[].rip)
			debug.write(', r8=')
			debug.write_address(current.registers[].r8)
			debug.write(', rcx=')
			debug.write_address(current.registers[].rcx)
		}

		debug.write_line()

		# Choose the next process to execute
		next = pick()
		if next === none return

		# Switch to the next process
		enter(frame, next)
	}
}

test() {
	registers = StaticAllocator.instance.allocate(capacityof(RegisterState)) as RegisterState*
	process = Process(0, registers) using StaticAllocator.instance

	# TODO: Create a test process
	# Instructions:
	# mov r8, 42
	# L0:
	# inc r8
	# jmp L0
	start = 0x150000 as link
	stack = 0x170000 as link

	start[0] = 0x49
	start[1] = 0xc7
	start[2] = 0xc0
	start[3] = 0x07
	start[4] = 0x00
	start[5] = 0x00
	start[6] = 0x00

	start[7] = 0x48
	start[8] = 0xc7
	start[9] = 0xc1
	start[10] = 0x2a
	start[11] = 0x00
	start[12] = 0x00
	start[13] = 0x00

	start[14] = 0x49
	start[15] = 0xff
	start[16] = 0xc0
	start[17] = 0xeb
	start[18] = 0xfb

	process.registers[].rip = start
	process.registers[].cs = 8
	process.registers[].rflags = (1 <| 9)
	process.registers[].userspace_rsp = stack
	process.registers[].userspace_ss = 16

	interrupts.scheduler.add(process)

	next = interrupts.scheduler.pick()
	debug.write_line(next as i64)
	#interrupts.scheduler.current = process
}