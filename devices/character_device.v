namespace kernel.devices

Device CharacterDevice {
	init(major: u32, minor: u32) {
		Device(major, minor)
	}
}