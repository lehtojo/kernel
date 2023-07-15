namespace kernel.devices.gpu

constant FBIOGET_VSCREENINFO = 0x4600
constant FBIOPUT_VSCREENINFO = 0x4601
constant FBIOGET_FSCREENINFO = 0x4602

# Macro pixel consists of all color channel values.
# For example, RGB value (3, 7, 42) is a macro pixel.

constant FB_TYPE_PACKED_PIXELS = 0 # Macropixels are stored contiguously in a single plane
constant FB_TYPE_PLANES = 0 # Macropixels are split across multiple planes. The number of planes is equal to the number of bits per macropixel, with plane i'th storing i'th bit from all macropixels.

constant FB_VISUAL_TRUECOLOR = 2 # Each pixel is broken into color channels

constant FB_ACTIVATE_NOW = 0 # Apply the values immediately
constant FB_ACTIVATE_FORCE = 128 # Activate even if no change is detected

plain DisplayModeSetting {
	horizontal_stride: u64 # "Pitch"
	pixel_clock_in_khz: u64

	horizontal_active: u64
	horizontal_front_porch_pixels: u64
	horizontal_sync_time_pixels: u64
	horizontal_blank_pixels: u64

	vertical_active: u64
	vertical_front_porch_lines: u64
	vertical_sync_time_lines: u64
	vertical_blank_lines: u64

	horizontal_offset: u64 # "X offset"
	vertical_offset: u64 # "Y offset"
}

plain FramebufferInformation {
	id: u8[16]
	framebuffer_offset: u64
	framebuffer_size: u32
	type: u32
	type_auxiliary: u32
	visual: u32
	xpanstep: u16
	ypanstep: u16
	ywrapstep: u16
	padding: u16
	line_length: u32
	memory_mapped_io_offset: u32
	memory_mapped_io_size: u32
	accelerator: u32
	capabilities: u16
	reserved: u16[2]
}

pack FramebufferBitfield {
	offset: u32
	length: u32
	msb_right: u32
}

plain ScreenInformation {
	x_resolution: u32
	y_resolution: u32
	x_virtual_resolution: u32
	y_virtual_resolution: u32
	x_offset: u32
	y_offset: u32

	bits_per_pixel: u32
	grayscale: u32

	red: FramebufferBitfield
	green: FramebufferBitfield
	blue: FramebufferBitfield
	transparent: FramebufferBitfield

	non_standard_pixel_format: u32

	activate: u32

	height: u32
	width: u32

	accelerator_flags: u32

	pixel_clock: u32
	left_margin: u32
	right_margin: u32
	upper_margin: u32
	lower_margin: u32
	horizontal_sync_length: u32
	vertical_sync_length: u32
	sync: u32
	vmode: u32
	rotate: u32
	colorspace: u32
	reserved: u32[4]
}

Device GenericDisplayConnector {
	readable enabled: bool = false
	readable framebuffer: link
	readable framebuffer_size: u32
	inline current_mode: DisplayModeSetting

	init(major: u32, minor: u32, framebuffer: link, framebuffer_size: u32) {
		Device.init(major, minor)
		this.framebuffer = framebuffer
		this.framebuffer_size = framebuffer_size
	}

	open enable(): _ {}

	private get_screen_information(information: ScreenInformation): i32 {
		debug.write_line('Generic display connector: Loading screen information...')
		information.x_resolution = current_mode.horizontal_active
		information.y_resolution = current_mode.vertical_active
		information.x_virtual_resolution = current_mode.horizontal_stride
		information.y_virtual_resolution = current_mode.vertical_active
		information.x_offset = current_mode.horizontal_offset
		information.y_offset = current_mode.vertical_offset

		information.bits_per_pixel = 32
		information.grayscale = 0

		information.red.offset = 0
		information.red.length = 8
		information.red.msb_right = 0

		information.green.offset = 8
		information.green.length = 8
		information.green.msb_right = 0

		information.blue.offset = 16
		information.blue.length = 8
		information.blue.msb_right = 0

		information.transparent.offset = 24
		information.transparent.length = 8
		information.transparent.msb_right = 0

		information.non_standard_pixel_format = 0

		information.activate = 0

		information.height = current_mode.vertical_active
		information.width = current_mode.horizontal_active

		information.accelerator_flags = 0

		information.pixel_clock = current_mode.pixel_clock_in_khz
		information.left_margin = current_mode.horizontal_front_porch_pixels
		information.right_margin = current_mode.horizontal_sync_time_pixels
		information.upper_margin = current_mode.vertical_front_porch_lines
		information.lower_margin = current_mode.vertical_sync_time_lines
		information.horizontal_sync_length = current_mode.horizontal_blank_pixels
		information.vertical_sync_length = current_mode.vertical_blank_lines
		information.sync = 0
		information.vmode = 0
		information.rotate = 0
		information.colorspace = 0
		information.reserved[0] = 0
		information.reserved[1] = 0
		information.reserved[2] = 0
		information.reserved[3] = 0
		return 0
	}

	private set_screen_information(information: ScreenInformation): i32 {
		debug.write_line('Generic display connector: Setting screen information...')
		return 0
	}

	private get_framebuffer_information(information: FramebufferInformation): i32 {
		debug.write_line('Generic display connector: Loading framebuffer information...')
		information.framebuffer_offset = 0
		information.framebuffer_size = framebuffer_size
		information.type = FB_TYPE_PACKED_PIXELS
		information.type_auxiliary = 0
		information.visual = FB_VISUAL_TRUECOLOR
		information.xpanstep = 0
		information.ypanstep = 0
		information.ywrapstep = 0
		information.line_length = current_mode.horizontal_stride
		information.memory_mapped_io_offset = 0
		information.memory_mapped_io_size = 0
		information.accelerator = 0
		information.capabilities = 0
		information.reserved[0] = 0
		information.reserved[1] = 0
		return 0
	}

	override map(process: Process, allocation: ProcessMemoryRegion, virtual_address: u64) {
		debug.write_line('Display connector: Mapping framebuffer page')

		# Map the accessed framebuffer page
		# Todo: Do we need more checks?
		virtual_page = virtual_address & (-PAGE_SIZE)
		page_offset = virtual_page - (allocation.region.start as u64)
		framebuffer_physical_page = framebuffer + page_offset
		process.memory.paging_table.map_page(HeapAllocator.instance, virtual_page as link, framebuffer_physical_page, MAP_USER)

		return Optionals.new<i32>(0)
	}

	override control(request: u32, argument: u64) {
		if not enabled {
			enabled = true
			enable()
		}

		return when(request) {
			FBIOGET_VSCREENINFO => get_screen_information(argument as ScreenInformation),
			FBIOPUT_VSCREENINFO => set_screen_information(argument as ScreenInformation),
			FBIOGET_FSCREENINFO => get_framebuffer_information(argument as FramebufferInformation),
			else => -1
		}
	}

	override get_name() {
		return String.new('fb0')
	}
}