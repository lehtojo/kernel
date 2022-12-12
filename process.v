namespace kernel.scheduler

constant RFLAGS_INTERRUPT_FLAG = 1 <| 9

Process {
	constant NORMAL_PRIORITY = 50

	id: u64
	priority: u16 = NORMAL_PRIORITY
	registers: RegisterState*

	init(id: u64, registers: RegisterState*) {
		this.id = id
		this.registers = registers

		registers[].cs = CODE_SEGMENT
		registers[].rflags = RFLAGS_INTERRUPT_FLAG
		registers[].userspace_ss = DATA_SEGMENT
	}

	save(frame: TrapFrame*) {
		registers[] = frame[].registers[]
	}
}