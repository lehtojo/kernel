constant PAGE_SIZE = 0x1000

constant KiB = 1024
constant MiB = 1048576

namespace kernel {
	constant CODE_SEGMENT = 8
	constant DATA_SEGMENT = 16
}

export start(multiboot_information: link, interrupt_tables: link) {
	boot.console.initialize()
	boot.console.clear()
	boot.console.write_line('...')

	StaticAllocator.initialize()

	scheduler = kernel.scheduler.Scheduler(StaticAllocator.instance)
	kernel.interrupts.tables = interrupt_tables
	kernel.interrupts.scheduler = scheduler

	kernel.serial.initialize()

	regions = List<Segment>(StaticAllocator.instance)
	reservations = List<Segment>(StaticAllocator.instance)
	section_headers = List<kernel.elf.SectionHeader>(StaticAllocator.instance)

	kernel.multiboot.initialize(multiboot_information, regions, reservations, section_headers)

	# TODO: Reserve GDT and other similar tables, use insert_segment()?

	#LayerAllocator.initialize(reservations)

	kernel.interrupts.initialize()
	kernel.keyboard.initialize(StaticAllocator.instance)

	kernel.scheduler.test(StaticAllocator.instance)

	kernel.apic.initialize(StaticAllocator.instance)

	kernel.interrupts.enable()

	loop {}
}
