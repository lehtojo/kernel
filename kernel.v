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

	import 'C' full_memory_barrier(): _
	import 'C' wait_for_microseconds(microseconds: u64): _

	import 'C' system_call(number: u64, argument_0: u64, argument_1: u64, argument_2: u64, argument_3: u64, argument_4: u64, argument_5: u64): u64

	import 'C' save_fpu_state_xsave(destination: link): _
	import 'C' load_fpu_state_xrstor(source: link): _

	clear_boot_console_with_white(): _ {
		console = kernel.mapper.map_kernel_page(0xb8000 as link) as u64*

		loop (i = 0, i < 500, i++) {
			console[i] = 0xff20ff20ff20ff20 # Clear with white spaces
		}
	}

	save_fpu_state(destination: link): _ {
		save_fpu_state_xsave(destination)
	}

	load_fpu_state(source: link): _ {
		load_fpu_state_xrstor(source)
	}

	# Todo: Remove the multiplications (* 100) once proper waiting is supported
	wait_for_microsecond(): _ { wait_for_microseconds(1 * 100) }
	wait_for_millisecond(): _ { wait_for_microseconds(1000 * 100) }

	pack SymbolInformation {
		name: String
		address: link

		shared new(name: String, address: link): SymbolInformation {
			return pack { name: name, address: address } as SymbolInformation
		}
	}

	plain SystemMemoryInformation {
		shared instance: SystemMemoryInformation

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
import kernel.devices.keyboard

# Todo: Too direct imports, abstract or remove
import kernel.file_systems.memory_file_system
import kernel.file_systems.ext2
import kernel.file_systems

export start(
	multiboot_information: link,
	interrupt_tables: link,
	interrupt_stack_pointer: link,
	gdtr_physical_address: link
) {
	serial.initialize()

	allocator = BufferAllocator(buffer: u8[0x4000], 0x4000)

	clear_boot_console_with_white()

	interrupts.tables = interrupt_tables
	interrupts.scheduler = scheduler.Scheduler()

	memory_information = SystemMemoryInformation()
	SystemMemoryInformation.instance = memory_information
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

	interrupts.scheduler.initialize_processes()

	Processor.count = 1
	Processor.initialize(interrupt_stack_pointer, gdtr_physical_address, 0)
	mapper.remap()

	interrupts.initialize()
	ps2.keyboard.initialize(allocator)

	devices = Devices(HeapAllocator.instance)
	Devices.instance = devices

	boot_console = BootConsoleDevice(HeapAllocator.instance)
	devices.add(boot_console)

	scheduler.create_idle_process()

	interrupts.apic.initialize(allocator)

	system_calls.initialize()

	kernel_thread_start = () -> {
		debug.write_line('Kernel thread: Starting...')

		Ext2.instance.initialize()

		FileSystem.root = Ext2.instance
		Custody.root = Custody(String.empty, none as Custody, Ext2.root_inode) using KernelHeap

		add_system_inodes(HeapAllocator.instance)

		require(Devices.instance.find(BootConsoleDevice.MAJOR, BootConsoleDevice.MINOR) has boot_console, 'Missing boot console')
		scheduler.create_boot_shell_process(HeapAllocator.instance, boot_console)

		debug.write_line('Kernel thread: All done')

		# Exit this thread
		system_call(0x3c, 0, 0, 0, 0, 0, 0)
	}

	kernel_thread = scheduler.create_kernel_thread(kernel_thread_start as u64)
	interrupts.enable()

	loop {}
}
