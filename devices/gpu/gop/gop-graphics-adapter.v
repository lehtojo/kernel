namespace kernel.devices.gpu.gop

GenericGraphicsAdapter GraphicsAdapter {
	shared create(uefi: UefiInformation): GraphicsAdapter {
		adapter = GraphicsAdapter() using KernelHeap
		adapter.initialize(uefi)

		return adapter
	}

	initialize(uefi: UefiInformation): _ {
		debug.write_line('GOP graphics adapter: Initializing...')

		framebuffer_physical_address = uefi.graphics_information.framebuffer_physical_address as link
		framebuffer_space_size = uefi.graphics_information.framebuffer_space_size
		horizontal_stride = uefi.graphics_information.horizontal_stride
		width = uefi.graphics_information.width
		height = uefi.graphics_information.height

		debug.write('GOP graphics adapter: ')
		debug.write('framebuffer=') debug.write_address(framebuffer_physical_address)
		debug.write(', framebuffer-space-size=') debug.write_address(framebuffer_space_size)
		debug.write(', horizontal-stride=') debug.write_address(horizontal_stride)
		debug.write(', width=') debug.write_address(width)
		debug.write(', height=') debug.write_address(height)
		debug.write_line()

		connector = DisplayConnector(framebuffer_physical_address, framebuffer_space_size) using KernelHeap
		connector.enable()
		connector.current_mode.horizontal_stride = horizontal_stride
		connector.current_mode.horizontal_active = width
		connector.current_mode.vertical_active = height
		DisplayConnectors.add(connector)
		Devices.instance.add(connector)

		# Change to this display connector as during UEFI boot GOP is the default
		DisplayConnectors.change(connector)
	}
}