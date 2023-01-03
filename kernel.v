constant PAGE_SIZE = 0x1000

constant KiB = 1024
constant MiB = 1048576

namespace kernel {
	constant KERNEL_CODE_SELECTOR = 0x8
	constant KERNEL_DATA_SELECTOR = 0x10

	constant USER_DATA_SELECTOR = 0x18
	constant USER_CODE_SELECTOR = 0x20

	constant KERNEL_MAP_BASE = 0xFFFF800000000000
	constant KERNEL_MAP_BASE_L4 = 0x100

	import 'C' write_cr4(value: u64)
	import 'C' read_cr4(): u64

	# Summary: Reads the contents of a 64-bit model specific register specified by the id
	import 'C' read_msr(id: u64): u64

	# Summary: Sets the contents of a 64-bit model specific register specified by the id
	import 'C' write_msr(id: u64, value: u64)

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
		physical_memory_manager_virtual_address: link
		quickmap_physical_base: link
	}
}

export start(multiboot_information: link, interrupt_tables: link, interrupt_stack_pointer: link) {
	kernel.serial.initialize()

	kernel.mapper.print_kernel_entry()
	kernel.mapper.initialize()

	allocator = BufferAllocator(buffer: u8[0x2000], 0x2000)

	boot.console.initialize()
	boot.console.clear()
	boot.console.write_line('...')

	scheduler = kernel.scheduler.Scheduler(allocator)
	kernel.interrupts.tables = interrupt_tables
	kernel.interrupts.scheduler = scheduler

	memory_information = kernel.SystemMemoryInformation()
	memory_information.regions = List<Segment>(allocator)
	memory_information.reserved = List<Segment>(allocator)
	memory_information.sections = List<kernel.elf.SectionHeader>(allocator)
	memory_information.symbols = List<kernel.SymbolInformation>(allocator)

	kernel.multiboot.initialize(multiboot_information, memory_information)

	# Tell the mapper where the quickmap base is, so that quickmapping is possible
	kernel.mapper.quickmap_physical_base = memory_information.quickmap_physical_base

	PhysicalMemoryManager.initialize(memory_information)
	kernel.KernelHeap.initialize()
	kernel.HeapAllocator.initialize(allocator)

	kernel.interrupts.initialize()
	kernel.keyboard.initialize(allocator)

	kernel.scheduler.test(allocator)
	kernel.scheduler.test2(kernel.HeapAllocator.instance, memory_information)

	kernel.apic.initialize(allocator)

	kernel.system_calls.initialize()
	kernel.Processor.initialize(interrupt_stack_pointer)

	kernel.interrupts.enable()

	loop {}
}
