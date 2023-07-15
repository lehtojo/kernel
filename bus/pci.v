namespace kernel.bus.pci

import kernel.acpi
import kernel.system_calls

interrupts_devices: Device[interrupts.MAX_ALLOCATED_INTERRUPTS]

constant PCI_CAPABILITY_ID_NULL = 0x00
constant PCI_CAPABILITY_ID_MSI = 0x05
constant PCI_CAPABILITY_ID_VENDOR_SPECIFIC = 0x09
constant PCI_CAPABILITY_ID_MSIX = 0x11

constant BAR_SPACE_TYPE_32_BIT = 0
constant BAR_SPACE_TYPE_16_BIT = 1
constant BAR_SPACE_TYPE_64_BIT = 2
constant BAR_SPACE_TYPE_IO_SPACE = 3

constant BAR_ADDRESS_MASK = 0xfffffff0

initialize(): _ {
	# Zero out the allocated interrupts, because we do not want garbage values as non-zero entry means an allocated interrupt
	memory.zero(interrupts_devices, interrupts.MAX_ALLOCATED_INTERRUPTS * strideof(Device))
}

# Summary: Allocates an interrupt for the specified device
allocate_interrupt(device: Device): u8 {
	interrupt = interrupts.allocate_interrupt((interrupt: u8, frame: RegisterState*) -> process_interrupt(interrupt, frame))
	interrupts_devices[interrupt - interrupts.FIRST_ALLOCATED_INTERRUPT] = device
	return interrupt
}

# Summary: Forwards an interrupt for a device
process_interrupt(interrupt: u8, frame: RegisterState*): u64 {
	device = interrupts_devices[interrupt - interrupts.FIRST_ALLOCATED_INTERRUPT]
	require(device !== none, 'Received interrupt for unallocated interrupt')

	return device.interrupt(interrupt, frame)
}

get_controller(identifier: DeviceIdentifier): HostController {
	controller = Parser.instance.find_host_contoller(identifier)
	require(controller !== none, 'Failed to find host controller using identifier')
	return controller
}

read_u16(identifier: DeviceIdentifier, offset: u32): u16 {
	return get_controller(identifier).read_u16(identifier.address.bus, identifier.address.device, identifier.address.function, offset)
}

read_u32(identifier: DeviceIdentifier, offset: u32): u32 {
	return get_controller(identifier).read_u32(identifier.address.bus, identifier.address.device, identifier.address.function, offset)
}

write_u16(identifier: DeviceIdentifier, offset: u32, value: u16): _ {
	get_controller(identifier).write_u16(identifier.address.bus, identifier.address.device, identifier.address.function, offset, value)
}

write_u32(identifier: DeviceIdentifier, offset: u32, value: u32): _ {
	get_controller(identifier).write_u32(identifier.address.bus, identifier.address.device, identifier.address.function, offset, value)
}

read_bar(identifier: DeviceIdentifier, bar: u8): u32 {
	require(bar >= 0 and bar <= 5, 'Invalid PCI BAR')

	return when(bar) {
		0 => read_u32(identifier, REGISTER_BAR0),
		1 => read_u32(identifier, REGISTER_BAR1),
		2 => read_u32(identifier, REGISTER_BAR2),
		3 => read_u32(identifier, REGISTER_BAR3),
		4 => read_u32(identifier, REGISTER_BAR4),
		5 => read_u32(identifier, REGISTER_BAR5)
	}
}

get_bar_space_type(bar_value: u32): u32 {
	# Note: If the first is set, the space type is IO space
	if (bar_value & 1) != 0 return BAR_SPACE_TYPE_IO_SPACE

	return (bar_value |> 1) & 0b11
}

get_bar_space_size(identifier: DeviceIdentifier, bar: u8): u64 {
	# PCI Spec 2.3, Page 222
	require(bar <= 5, 'Invalid PCI BAR')
	field = REGISTER_BAR0 + (bar <| 2)
	bar_reserved = read_u32(identifier, field)
	write_u32(identifier, field, 0xffffffff)
	space_size = read_u32(identifier, field)
	write_u32(identifier, field, bar_reserved)
	space_size &= BAR_ADDRESS_MASK
	space_size = ((!space_size) + 1) & 0xffffffff
	return space_size
}

enable_bus_mastering(identifier: DeviceIdentifier): _ {
	debug.write('PCI: Enabling bus mastering for ') debug.write_address(identifier.address.value) debug.write_line()

	value = read_u16(identifier, REGISTER_COMMAND)
	value |= 0b100
	value |= 0b001
	write_u16(identifier, REGISTER_COMMAND, value)
}

enable_memory_space(identifier: DeviceIdentifier): _ {
	debug.write('PCI: Enabling memory space for ') debug.write_address(identifier.address.value) debug.write_line()

	value = read_u16(identifier, REGISTER_COMMAND)
	value |= 0b10
	write_u16(identifier, REGISTER_COMMAND, value)
}

create_io_window_for_pci_device_bar(identifier: DeviceIdentifier, bar: u8, size: u64): Result<link, u64> {
	require(bar <= 5, 'Invalid PCI BAR')

	debug.write('PCI: Creating IO window of ')
	debug.write_address(size)
	debug.write(' byte(s) for ')
	debug.write_address(identifier.address.value)
	debug.write(' (BAR')
	debug.write(bar as i64)
	debug.write_line(')')

	bar_value = read_bar(identifier, bar)
	bar_space_type = get_bar_space_type(bar_value)

	if bar_space_type == BAR_SPACE_TYPE_64_BIT {
		if bar == 5 {
			debug.write_line('PCI: Warning: Creating IO window for BAR5 with 64-bit memory space')
		}

		next_bar_value = read_bar(identifier, bar + 1)
		bar_value |= (next_bar_value <| 32)
	}

	bar_space_size = get_bar_space_size(identifier, bar)

	# Verify we have enough space
	if bar_space_size < size return Results.error<link, u64>(EIO)

	if bar_space_type == BAR_SPACE_TYPE_IO_SPACE {
		panic('Todo')
	}

	# Todo: Check for overflows

	# Map the space so that we can use it
	bar_space_address = bar_value & BAR_ADDRESS_MASK
	return Results.new<link, u64>(mapper.map_kernel_region(bar_space_address as link, size, MAP_NO_CACHE))
}

create_io_window_for_pci_device_bar(identifier: DeviceIdentifier, bar: u8): Result<link, u64> {
	return create_io_window_for_pci_device_bar(identifier, bar, get_bar_space_size(identifier, bar))
}

enable_interrupt_line(identifier: DeviceIdentifier): _ {
	debug.write('PCI: Enabling interrupt line ')  debug.write(identifier.interrupt_line)
	debug.write(' for ') debug.write_address(identifier.address.value) debug.write_line()

	value = read_u16(identifier, REGISTER_COMMAND)
	value &= !(1 <| 10)
	write_u16(identifier, REGISTER_COMMAND, value)
}

disable_interrupt_line(identifier: DeviceIdentifier): _ {
	debug.write('PCI: Disabling interrupt line ')  debug.write(identifier.interrupt_line)
	debug.write(' for ') debug.write_address(identifier.address.value) debug.write_line()

	value = read_u16(identifier, REGISTER_COMMAND)
	value |= (1 <| 10)
	write_u16(identifier, REGISTER_COMMAND, value)
}