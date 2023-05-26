namespace kernel.devices

import kernel.file_systems

CharacterDevice TeletypeDevice {
	init(major: u32, minor: u32) {
		CharacterDevice.init(major, minor)
	}

	override get_name() {
		return String.new('tty')
	}

	override can_read(description: OpenFileDescription) { return true }
	override can_write(description: OpenFileDescription) { return true }

	override write(description: OpenFileDescription, data: Array<u8>, offset: u64) {
		debug.write_line('Teletype device: Writing bytes...')
		debug.write_bytes(data.data, data.size)
		return 0	
	}
	
	override read(description: OpenFileDescription, destination: link, offset: u64, size: u64) {
		debug.write_line('Teletype device: Reading bytes...')
		return 0
	}
}