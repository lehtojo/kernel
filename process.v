namespace kernel.scheduler

constant SEGMENT_CODE = 1
constant SEGMENT_DATA = 2
constant SEGMENT_STACK = 3

constant RFLAGS_INTERRUPT_FLAG = 1 <| 9

pack Segment {
	type: i8
	start: link
	end: link
}

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