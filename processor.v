namespace kernel

constant MSR_GS_BASE = 0xc0000101

plain Processor {
	padding: link
	kernel_stack_pointer: link
	user_stack_pointer: link

	shared initialize(kernel_stack_pointer: link) {
		processor = Processor() using KernelHeap
		processor.kernel_stack_pointer = kernel_stack_pointer

		write_msr(MSR_GS_BASE, processor as u64)
	}

	# Summary: Returns the processor data structure that the currently executing processor owns.
	shared current(): Processor {
		return read_msr(MSR_GS_BASE) as Processor
	}
}