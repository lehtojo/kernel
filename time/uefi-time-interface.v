namespace kernel.time

import kernel.system_calls

TimeInterface UefiTimeInterface {
	uefi: UefiInformation

	init(uefi: UefiInformation) {
		this.uefi = uefi
	}

	override get_time(time: DateTime) {
		debug.write_line('Uefi time interface: Getting current time...')

		uefi_scope!(uefi,
			runtime_services = uefi.system_table.runtime_services
			result = call_uefi(runtime_services.get_time, time, none as link)
		)

		if result == 0 return 0

		debug.write('Uefi time interface: Failed to get current time with result code ') debug.write_line(result)
		return EIO
	}

	override set_time(time: DateTime) {
		panic('Uefi time interface: Setting time is not supported yet')
		return ENOTSUP
	}
}