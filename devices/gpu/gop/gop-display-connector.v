namespace kernel.devices.gpu.gop

import kernel.acpi
import kernel.system_calls

GenericDisplayConnector DisplayConnector {
	init(framebuffer: link, framebuffer_space_size: u64) {
		# Todo: Figure out the device id
		GenericDisplayConnector.init(0x8765, 0x4321, framebuffer, framebuffer_space_size)
	}

	override enable() {
		debug.write_line('GOP display connector: Enabling...')
		enable_default()
		unblank()
		set_safe_display_mode_setting()
	}

	unblank(): _ {
		debug.write_line('GOP display connector: Unblank')
	}

	set_safe_display_mode_setting(): u64 {
		return 0
	}

	set_display_mode_setting(mode: DisplayModeSetting): u64 {
		debug.write_line('GOP display connector: Setting display mode setting...')
		return ENOTSUP
	}

	override get_name() {
		return String.new('fb0')
	}
}