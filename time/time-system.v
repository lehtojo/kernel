namespace kernel.time

plain Time {
	shared instance: Time

	private interface: TimeInterface

	shared initialize(allocator: Allocator, uefi: UefiInformation): _ {
		interface: TimeInterface = UefiTimeInterface(uefi) using allocator
		instance = Time(interface) using allocator

		DateTime.UNIX_EPOCH = DateTime(1970, 1, 1, 0, 0, 0, 0, TIME_ZONE_UNSPECIFIED, 0) using allocator
	}

	init(interface: TimeInterface) {
		this.interface = interface
	}

	get_time(time: DateTime): u64 {
		return interface.get_time(time)
	}

	output_current_time(): _ {
		time = DateTime()
		if get_time(time) != 0 return

		debug.write('System time: ') time.output() debug.write_line()
	}
}