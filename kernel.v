constant PAGE_SIZE = 0x1000

constant KiB = 1024
constant MiB = 1048576

namespace kernel {
	constant CODE_SEGMENT = 8
	constant DATA_SEGMENT = 16

	pack SymbolInformation {
		name: String
		address: link

		shared new(name: String, address: link): SymbolInformation {
			return pack { name: name, address: address } as SymbolInformation
		}
	}

	plain SystemMemoryInformation {
		regions: List<Segment>
		reserved: List<Segment>
		sections: List<elf.SectionHeader>
		symbols: List<SymbolInformation>
		physical_memory_size: u64
	}
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

	memory_information = kernel.SystemMemoryInformation()
	memory_information.regions = List<Segment>(allocator)
	memory_information.reserved = List<Segment>(allocator)
	memory_information.sections = List<kernel.elf.SectionHeader>(allocator)
	memory_information.symbols = List<kernel.SymbolInformation>(allocator)

	layer_allocator_address = kernel.multiboot.initialize(multiboot_information, memory_information)

	PhysicalMemoryManager.initialize(layer_allocator_address, memory_information)
	kernel.KernelHeap.initialize()
	kernel.HeapAllocator.initialize(allocator)

	kernel.interrupts.initialize()
	kernel.keyboard.initialize(allocator)

	kernel.scheduler.test(allocator)
	kernel.scheduler.test2(kernel.HeapAllocator.instance, memory_information)

	kernel.apic.initialize(allocator)

	kernel.interrupts.enable()

	loop {}
}
