constant KiB = 1024
constant MiB = 1048576

import 'C' test_interrupt()

export init() {
	boot.console.initialize()
	boot.console.clear()
	boot.console.write_line('...')

	scheduler = kernel.scheduler.Scheduler.new(none as Allocator)
	interrupts.scheduler = scheduler

	kernel.serial.initialize()

	interrupts.initialize()
	kernel.keyboard.initialize()

	debug.write_line(interrupts.internal.get_interrupt_handler() as u64)

	test_interrupt()

	interrupts.enable()

	apic.initialize()

	loop {}
}
