namespace kernel.devices.gpu.qemu

import kernel.acpi
import kernel.system_calls

constant FRAMEBUFFER_SETTING_ENABLED = 1
constant FRAMEBUFFER_SETTING_LINEAR_FRAMEBUFFER = 0x40

constant BYTEORDER_LITTLE_ENDIAN = 0x1e1e1e1e

constant VBE_DISPI_ID5 = 0xb0c5

GenericDisplayConnector DisplayConnector {
	registers: DisplayMemoryMappedIORegisters

	init(framebuffer: link, framebuffer_space_size: u64, registers: DisplayMemoryMappedIORegisters) {
		GenericDisplayConnector.init(0x1234, 0x5678, framebuffer, framebuffer_space_size)
		this.registers = registers
	}

	override enable() {
		debug.write_line('QEMU display connector: Enabling...')
		unblank()
		set_safe_display_mode_setting()
	}

	unblank(): _ {
		debug.write_line('QEMU display connector: Unblank')
		full_memory_barrier()
		registers.vga_ioports[] = 0x20
		full_memory_barrier()
	}

	set_safe_display_mode_setting(): u64 {
		mode = DisplayModeSetting()
      mode.horizontal_stride = 1024 * sizeof(u32),
      mode.pixel_clock_in_khz = 0 # Note: Unused
      mode.horizontal_active = 1024
      mode.horizontal_front_porch_pixels = 0 # Note: Unused
      mode.horizontal_sync_time_pixels = 0 # Note: Unused
      mode.horizontal_blank_pixels = 0 # Note: Unused
      mode.vertical_active = 768
      mode.vertical_front_porch_lines = 0 # Note: Unused
      mode.vertical_sync_time_lines = 0 # Note: Unused
      mode.vertical_blank_lines = 0 # Note: Unused
      mode.horizontal_offset = 0
      mode.vertical_offset = 0
		return set_display_mode_setting(mode)
	}

	set_framebuffer_to_little_endian(): _ {
		full_memory_barrier()
		if registers.extension_registers.region_size == 0xffffffff or registers.extension_registers.region_size == 0 return

		full_memory_barrier()
		registers.extension_registers.framebuffer_byteorder = BYTEORDER_LITTLE_ENDIAN
		full_memory_barrier()
	}

	set_display_mode_setting(mode: DisplayModeSetting): u64 {
		debug.write_line('QEMU display connector: Setting display mode setting...')

		width = mode.horizontal_active
		height = mode.vertical_active

		registers.registers.enable = 0
		full_memory_barrier()

		registers.registers.x_resolution = width
		registers.registers.y_resolution = height
		registers.registers.virtual_width = width
		registers.registers.virtual_height = height
		registers.registers.bpp = 32

		full_memory_barrier()
		registers.registers.enable = FRAMEBUFFER_SETTING_ENABLED | FRAMEBUFFER_SETTING_LINEAR_FRAMEBUFFER
		full_memory_barrier()
		registers.registers.bank = 0

		if registers.registers.index_id == VBE_DISPI_ID5 { set_framebuffer_to_little_endian() }

		# Verify the resolution changed
		if width != registers.registers.x_resolution or height != registers.registers.y_resolution {
			return ENOTSUP
		}

		# Update the current display mode setting
		memory.zero(current_mode as link, sizeof(DisplayModeSetting))
		current_mode.horizontal_stride = width * sizeof(u32)
		current_mode.horizontal_active = width
		current_mode.vertical_active = height

		debug.write_line('QEMU display connector: Successfully set display mode setting')
		return 0
	}
}