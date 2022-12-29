namespace kernel.system_calls

constant SYSTEM_CALL_ERROR_NO_MEMORY = -1

export process(frame: TrapFrame*) {
	registers = frame[].registers
	system_call_number = registers[].rax

	if system_call_number == 1 {
		system_write(registers[].rdi as u32, registers[].rsi as link, registers[].rdx)
	} else system_call_number == 9 {
		system_memory_map(
			registers[].rdi as link, registers[].rsi, registers[].rdx as u32,
			registers[].r10 as u32, registers[].r8 as u32, registers[].r9
		)
	} else {
		panic('Unsupported system call')
	}
}