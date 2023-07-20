namespace kernel.devices.gpu.qemu

import kernel.bus
import kernel.acpi

pack DISPIInterface {
	index_id: u16
	x_resolution: u16
	y_resolution: u16
	bpp: u16
	enable: u16
	bank: u16
	virtual_width: u16
	virtual_height: u16
	x_offset: u16
	y_offset: u16
	vram_64k_chunks_count: u16
}

pack ExtensionRegisters {
	region_size: u32
	framebuffer_byteorder: u32
}

plain DisplayMemoryMappedIORegisters {
	edid: u8[0x400]
	vga_ioports: u16[0x10]
	reserved_1: u8[0xe0]
	registers: DISPIInterface
	reserved_2: u8[0xea]
	extension_registers: ExtensionRegisters
}

GenericGraphicsAdapter Device GraphicsAdapter {
	shared create(identifier: DeviceIdentifier): GraphicsAdapter {
		adapter = GraphicsAdapter(identifier) using KernelHeap
		adapter.initialize()		

		return adapter
	}

	init(identifier: DeviceIdentifier) {
		Device.init(identifier)
	}

	initialize(): _ {
		debug.write_line('QEMU graphics adapter: Initializing...')
		framebuffer_space_size = pci.get_bar_space_size(identifier, 0)

		# For now we only support memory mapped IO registers (QEMU)
		framebuffer_physical_address = pci.read_bar_address(identifier, 0)
		registers_physical_address = pci.read_bar_address(identifier, 2)

		debug.write('QEMU graphics adapter: ')
		debug.write('framebuffer=') debug.write_address(framebuffer_physical_address)
		debug.write(', framebuffer-space-size=') debug.write_address(framebuffer_space_size)
		debug.write(', registers=') debug.write_address(registers_physical_address)
		debug.write_line()

		mapped_registers = mapper.map_kernel_page(registers_physical_address as link, MAP_NO_CACHE)

		connector = DisplayConnector(framebuffer_physical_address as link, framebuffer_space_size, mapped_registers as DisplayMemoryMappedIORegisters) using KernelHeap
		Devices.instance.add(connector)
	}
}