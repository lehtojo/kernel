namespace kernel

constant MSR_GS_BASE = 0xc0000101

plain Processor {
	shared count: u32

	temporary: link
	kernel_stack_pointer: link
	user_stack_pointer: link
	general_kernel_stack_pointer: link
	gdtr_physical_address: link
	index: u32

	shared initialize(kernel_stack_pointer: link, gdtr_physical_address: link, index: u32) {
		processor = Processor() using KernelHeap
		debug.write('Processor: Address = ') debug.write_address(processor as link) debug.write_line()

		processor.kernel_stack_pointer = kernel_stack_pointer
		processor.general_kernel_stack_pointer = kernel_stack_pointer
		processor.gdtr_physical_address = gdtr_physical_address
		processor.index = index

		write_msr(MSR_GS_BASE, processor as u64)
	}

	# Summary: Returns the processor data structure that the currently executing processor owns.
	shared current(): Processor {
		return read_msr(MSR_GS_BASE) as Processor
	}
}