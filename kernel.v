constant PAGE_SIZE = 0x1000

constant KiB = 1024
constant MiB = 1048576

namespace kernel {
	constant KERNEL_CODE_SELECTOR = 0x8
	constant KERNEL_DATA_SELECTOR = 0x10

	constant USER_DATA_SELECTOR = 0x18
	constant USER_CODE_SELECTOR = 0x20

	constant KERNEL_MAP_BASE = 0xFFFF800000000000
	constant KERNEL_MAP_END = 0xFFFF808000000000
	constant KERNEL_MAP_BASE_L4 = 0x100

	constant GDTR_VIRTUAL_ADDRESS = 0x100000000000

	import 'C' write_cr0(value: u64)
	import 'C' write_cr1(value: u64)
	import 'C' write_cr2(value: u64)
	import 'C' write_cr3(value: u64)
	import 'C' write_cr4(value: u64)
	import 'C' write_fs_base(value: u64)
	import 'C' read_fs_base(): u64

	import 'C' read_cr0(): u64
	import 'C' read_cr1(): u64
	import 'C' read_cr2(): u64
	import 'C' read_cr3(): u64
	import 'C' read_cr4(): u64

	import 'C' write_gdtr(value: u64)

	# Summary: Reads the contents of a 64-bit model specific register specified by the id
	import 'C' read_msr(id: u64): u64

	# Summary: Sets the contents of a 64-bit model specific register specified by the id
	import 'C' write_msr(id: u64, value: u64)

	import 'C' registers_rsp(): u64
	import 'C' registers_rip(): u64

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

import kernel
import kernel.devices
import kernel.devices.console

export start(
	multiboot_information: link,
	interrupt_tables: link,
	interrupt_stack_pointer: link,
	gdtr_physical_address: link
) {
	serial.initialize()

	allocator = BufferAllocator(buffer: u8[0x4000], 0x4000)

	boot.console.initialize()
	boot.console.clear()
	boot.console.write_line('...')

	interrupts.tables = interrupt_tables
	interrupts.scheduler = scheduler.Scheduler(allocator)

	memory_information = SystemMemoryInformation()
	memory_information.regions = List<Segment>(allocator)
	memory_information.reserved = List<Segment>(allocator)
	memory_information.sections = List<elf.SectionHeader>(allocator)
	memory_information.symbols = List<SymbolInformation>(allocator)

	multiboot.initialize(multiboot_information, memory_information)

	# Tell the mapper where the quickmap base is, so that quickmapping is possible
	mapper.quickmap_physical_base = memory_information.quickmap_physical_base

	PhysicalMemoryManager.initialize(memory_information)
	KernelHeap.initialize()
	HeapAllocator.initialize(allocator)

	interrupts.scheduler.processes = List<scheduler.Process>(HeapAllocator.instance) using KernelHeap

	Processor.initialize(interrupt_stack_pointer, gdtr_physical_address)
	mapper.remap()

	interrupts.initialize()
	keyboard.initialize(allocator)

	scheduler.test(allocator)
	scheduler.test(allocator)
	scheduler.test2(HeapAllocator.instance, memory_information)

	apic.initialize(allocator)

	devices = Devices(HeapAllocator.instance)
	console = ConsoleDevice(HeapAllocator.instance, 42, 42)
	devices.add(console)

	file_systems.memory_file_system.test(HeapAllocator.instance, memory_information, devices)

	system_calls.initialize()

	interrupts.enable()

	loop {}
}
