constant PAGE_SIZE = 0x1000

constant KiB = 1024
constant MiB = 1048576

namespace kernel {
	constant CODE_SEGMENT = 8
	constant DATA_SEGMENT = 16
}

export start(multiboot_information: link, interrupt_tables: link) {
	allocator = BufferAllocator(buffer: u8[0x2000], 0x2000)

	boot.console.initialize()
	boot.console.clear()
	boot.console.write_line('...')

	scheduler = kernel.scheduler.Scheduler(allocator)
	kernel.interrupts.tables = interrupt_tables
	kernel.interrupts.scheduler = scheduler

	kernel.serial.initialize()

	regions = List<Segment>(allocator)
	reservations = List<Segment>(allocator)
	section_headers = List<kernel.elf.SectionHeader>(allocator)

	kernel.multiboot.initialize(multiboot_information, regions, reservations, section_headers)

	# TODO: Reserve GDT and other similar tables, use insert_segment()?

	#LayerAllocator.initialize(reservations)

	kernel.interrupts.initialize()
	kernel.keyboard.initialize(allocator)

	kernel.scheduler.test(allocator)

	kernel.apic.initialize(allocator)

	kernel.interrupts.enable()

	loop {}
}
