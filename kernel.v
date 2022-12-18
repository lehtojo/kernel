constant PAGE_SIZE = 0x1000

constant KiB = 1024
constant MiB = 1048576

namespace kernel {
	constant CODE_SEGMENT = 8
	constant DATA_SEGMENT = 16
}

import 'C' test_interrupt()

export start(information: link) {
	boot.console.initialize()
	boot.console.clear()
	boot.console.write_line('...')

	StaticAllocator.initialize()

	# TODO: Figure out how to get the memory map from the BIOS
	# TODO: Once the memory map is here, reserve certain memory regions

	#LayerAllocator.initialize(none as link, 0)
	#LayerAllocator.instance.allocate(PAGE_SIZE, 0x300000 as link)

	scheduler = kernel.scheduler.Scheduler(StaticAllocator.instance)
	interrupts.scheduler = scheduler

	kernel.serial.initialize()

	regions = List<Segment>(StaticAllocator.instance)
	reservations = List<Segment>(StaticAllocator.instance)
	section_headers = List<kernel.elf.SectionHeader>(StaticAllocator.instance)

	kernel.multiboot.initialize(information, regions, reservations, section_headers)

	# TODO: Reserve GDT and other similar tables, use insert_segment()?

	#LayerAllocator.initialize(reservations)

	interrupts.initialize()
	kernel.keyboard.initialize(StaticAllocator.instance)

	kernel.scheduler.test(StaticAllocator.instance)

	test_interrupt()

	apic.initialize()

	interrupts.enable()

	loop {}
}
