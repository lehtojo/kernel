constant PAGE_SIZE = 0x1000

constant KiB = 0x400
constant MiB = 0x100000
constant GiB = 0x40000000

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

	import 'C' uefi_call_wrapper(function: link, argument_0: u64, argument_1: u64): _

	call_uefi(function: link, argument_0, argument_1) {
		debug.write('UEFI: Calling ') debug.write_address(function) debug.write(' with arguments ')
		debug.write_address(argument_0 as u64) debug.write(', ') debug.write_address(argument_1 as u64) debug.write_line()
		uefi_call_wrapper(function, argument_0 as u64, argument_1 as u64)
	}

	# Summary: Returns whether the specified result code is an error
	is_error_code(code: u64) {
		return (code as i64) < 0
	}

	clear_boot_console_with_white(): _ {
		console = kernel.mapper.map_kernel_page(0xb8000 as link, MAP_NO_CACHE) as u64*

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

	plain UefiTableHeader {
		signature: u64
		revision: u32
		header_size: u32
		crc32: u32
		reserved: u32
	}

	pack UefiGuid {
		data1: u32
		data2: u16
		data3: u16
		data4: u64

		shared new(data1: u32, data2: u16, data3: u16, data4_1: u8, data4_2: u8, data4_3: u8, data4_4: u8, data4_5: u8, data4_6: u8, data4_7: u8, data4_8: u8): UefiGuid {
			data4: u64 = data4_1 | (data4_2 <| 8) | (data4_3 <| 16) | (data4_4 <| 24) | (data4_5 <| 32) | (data4_6 <| 40) | (data4_7 <| 48) | (data4_8 <| 56)
			return pack { data1: data1, data2: data2, data3: data3, data4: data4 } as UefiGuid
		}
	}

	pack UefiConfigurationTable {
		vendor_guid: UefiGuid
		vendor_table: link
	}

	plain UefiSystemTable {
		inline header: UefiTableHeader
		firmware_vendor: link
		firmware_revision: u32
		padding: u32
		console_in_handle: link
		console_in: link
		console_out_handle: link
		console_out: UefiSimpleTextOutputInterface
		console_error_handle: link
		console_error: link
		runtime_services: link
		boot_services: link
		number_of_table_entries: u64
		configuration_table: UefiConfigurationTable*
	}

	plain UefiSimpleTextOutputInterface {
		reset: link
		output_string: link
		test_string: link
		query_mode: link
		set_mode: link
		set_attribute: link
		clear_screen: link
		set_cursor_position: link
		enable_cursor: link
		mode: link
	}

	pack UefiGraphicsInformation {
		framebuffer_physical_address: u64
		horizontal_stride: u64
		width: u64
		height: u64

		framebuffer_space_size => width * height * sizeof(u32)
	}

	plain UefiInformation {
		system_table: UefiSystemTable
		regions: Segment*
		region_count: u64
		physical_memory_size: u64
		memory_map_end: u64
		bitmap_font_file: link
		bitmap_font_file_size: u64
		bitmap_font_descriptor_file: link
		bitmap_font_descriptor_file_size: u64
		graphics_information: UefiGraphicsInformation
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
import kernel.low

export start(
	multiboot_information: link,
	interrupt_tables: link,
	interrupt_stack_pointer: link,
	gdtr_physical_address: link,
	uefi_information: UefiInformation
) {
	serial.initialize()

	allocator = BufferAllocator(buffer: u8[0x4000], 0x4000)

	memory_information = SystemMemoryInformation()
	SystemMemoryInformation.instance = memory_information
	memory_information.regions = List<Segment>(allocator)
	memory_information.reserved = List<Segment>(allocator)
	memory_information.sections = List<elf.SectionHeader>(allocator)
	memory_information.symbols = List<SymbolInformation>(allocator)

	interrupts.tables = interrupt_tables
	interrupts.scheduler = scheduler.Scheduler()

	if uefi_information !== none {
		mapper.remap(allocator, gdtr_physical_address, memory_information, uefi_information)
	} else multiboot_information !== none {
		multiboot.initialize(multiboot_information, memory_information)
	}

	clear_boot_console_with_white()

	# Tell the mapper where the quickmap base is, so that quickmapping is possible
	mapper.quickmap_physical_base = memory_information.quickmap_physical_base

	PhysicalMemoryManager.initialize(memory_information)
	KernelHeap.initialize()
	HeapAllocator.initialize(allocator)

	if FramebufferConsole.instance !== none and uefi_information !== none {
		# Output console content to the actual framebuffer
		graphics_information = uefi_information.graphics_information
		framebuffer_size = graphics_information.horizontal_stride * graphics_information.height
		FramebufferConsole.instance.output_framebuffer = mapper.map_kernel_region(graphics_information.framebuffer_physical_address as link, framebuffer_size, MAP_NO_CACHE)
		FramebufferConsole.instance.output_framebuffer_horizontal_stride = graphics_information.horizontal_stride

		FramebufferConsole.instance.load_font(uefi_information as UefiInformation)
	}

	boot_console = BootConsoleDevice(HeapAllocator.instance)
	BootConsoleDevice.instance = boot_console

	interrupts.scheduler.initialize_processes()

	Processor.count = 1
	Processor.initialize(interrupt_stack_pointer, gdtr_physical_address, 0)

	if uefi_information === none {
		mapper.remap()
	}

	FileSystems.initialize(HeapAllocator.instance)

	interrupts.initialize()
	ps2.keyboard.initialize(allocator)

	devices = Devices(HeapAllocator.instance)
	Devices.instance = devices

	if uefi_information !== none {
		# Todo: Generalize
		adapter = kernel.devices.gpu.gop.GraphicsAdapter.create(uefi_information)
	}

	devices.add(boot_console)

	scheduler.create_idle_process()

	interrupts.apic.initialize(HeapAllocator.instance, uefi_information)

	system_calls.initialize()

	kernel_thread_start = () -> {
		debug.write_line('Kernel thread: Starting...')
		loop {}

		Ext2.instance.initialize()

		FileSystems.root = Ext2.instance
		Custody.root = Custody(String.empty, none as Custody, Ext2.root_inode) using KernelHeap

		add_system_inodes(HeapAllocator.instance)

		require(Devices.instance.find(BootConsoleDevice.MAJOR, BootConsoleDevice.MINOR) has boot_console, 'Missing boot console')
		scheduler.create_boot_shell_process(HeapAllocator.instance, boot_console)

		debug.write_line('Kernel thread: All done')

		# Do not redirect debug information to boot console anymore
		debug.booted = true

		# Exit this thread
		system_call(0x3c, 0, 0, 0, 0, 0, 0)
	}

	kernel_thread = scheduler.create_kernel_thread(kernel_thread_start as u64)
	interrupts.enable()

	loop {}
}
