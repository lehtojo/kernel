constant KiB = 1024
constant MiB = 1048576

namespace kernel {
	constant CODE_SEGMENT = 8
	constant DATA_SEGMENT = 16

	constant PAGE_SIZE = 0x1000
}

import 'C' test_interrupt()

export init() {
	boot.console.initialize()
	boot.console.clear()
	boot.console.write_line('...')

	StaticAllocator.initialize()

	scheduler = kernel.scheduler.Scheduler(StaticAllocator.instance) using StaticAllocator.instance
	interrupts.scheduler = scheduler

	kernel.serial.initialize()

	interrupts.initialize()
	kernel.keyboard.initialize()

	kernel.scheduler.test()

	debug.write_line(interrupts.internal.get_interrupt_handler() as u64)

	test_interrupt()

	interrupts.enable()

	apic.initialize()

	loop {}
}
