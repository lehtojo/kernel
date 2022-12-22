# AHCI (Advance Host Controller Interface)
namespace kernel.ahci

constant PORT_INTERFACE_POWER_MANAGEMENT_ACTIVE = 0x1
constant PORT_DETECTION_PRESENT = 0x3

constant SATA_SIGNATURE_ATA = 0x00000101 # SATA drive
constant SATA_SIGNATURE_ATAPI = 0xEB140101 # SATAPI drive
constant SATA_SIGNATURE_ENCLOSURE_MANAGEMENT_BRIDGE = 0xC33C0101 # Enclosure management bridge (SEMB)
constant SATA_SIGNATURE_PORT_MULTIPLIER = 0x96690101 # Port multiplier

constant AHCI_DEVICE_NONE = 0
constant AHCI_DEVICE_SATA = 1
constant AHCI_DEVICE_SATAPI = 2
constant AHCI_DEVICE_ENCLOSURE_MANAGEMENT_BRIDGE = 3
constant AHCI_DEVICE_PORT_MULTIPLIER = 4

constant AHCI_STATUS_FIS_RECEIVE_ENABLE = 0x0010   # FRE
constant AHCI_STATUS_FID_RECEIVE_RUNNING = 0x4000  # FR
constant AHCI_STATUS_COMMAND_LIST_START = 0x0001   # ST
constant AHCI_STATUS_COMMAND_LIST_RUNNING = 0x8000 # CR

constant PHYSICAL_REGION_DESCRIPTORS_PER_COMMAND_TABLE = 0x8
constant MAX_PHYSICAL_REGION_DESCRIPTORS_PER_COMMAND_TABLE = 0xffff

constant COMMAND_TABLES_PER_COMMAND_LIST = 32
constant MAX_NUMBER_OF_PORTS = 32

constant FIS_TYPE_REG_H2D = 0x27   # Register FIS - host to device
constant FIS_TYPE_REG_D2H = 0x34   # Register FIS - device to host
constant FIS_TYPE_DMA_ACT = 0x39   # DMA activate FIS - device to host
constant FIS_TYPE_DMA_SETUP = 0x41 # DMA setup FIS - bidirectional
constant FIS_TYPE_DATA = 0x46      # Data FIS - bidirectional
constant FIS_TYPE_BIST = 0x58      # BIST activate FIS - bidirectional
constant FIS_TYPE_PIO_SETUP = 0x5F # PIO setup FIS - device to host
constant FIS_TYPE_DEV_BITS	= 0xA1  # Set device bits FIS - device to host

# NOTE: Controller here refers to HBA

pack FIS_H2D {
	type: u8
	flags: u8
	command: u8
	feature_low: u8
	lba0: u8
	lba1: u8
	lba2: u8
	device: u8
	lba3: u8
	lba4: u8
	lba5: u8
	feature_high: u8
	count: u16
	isochronous_command_completion: u8
	control: u8
	reserved: u32
}

pack FIS_D2H {
	type: u8
	flags: u8
	status: u8
	error: u8
	lba0: u8
	lba1: u8
	lba2: u8
	device: u8
	lba3: u8
	lba4: u8
	lba5: u8
	reserved_1: u8
	count: u16
	reserved_2: u16
	reserved_3: u32
}

pack FIS_DATA {
	type: u8
	flags: u8
	reserved: u16

	# Payload
}

pack FIS_PIO_SETUP {
	type: u8
	flags: u8
	status: u8
	error: u8
	lba0: u8
	lba1: u8
	lba2: u8
	device: u8
	lba3: u8
	lba4: u8
	lba5: u8
	reserved_1: u8
	count: u16
	reserved_2: u8
	new_status: u8
	transfer_count: u16
	reserved_3: u32
}

pack FIS_DMA_SETUP {
	type: u8
	reserved_1: u8[2]
	dma_buffer_id: u64
	reserved_2: u32
	dma_buffer_offset: u32
	transfer_count: u32
	reserved_3: u32
}

pack FIS {
	dma_setup: FIS_DMA_SETUP
	padding_0: u8[4]
	pio_setup: FIS_PIO_SETUP
	padding_1: u8[4]
	register: FIS_D2H
	padding_2: u8[4]
	set_device_bits: u64
	unused: u8[64]
	reserved: u8[0x60]
}

plain ControllerInterface {
	host_capability: u32 # "The number of command lists (1-32)"
	global_host_control: u32
	interrupt_status: u32
	ports_implemented: u32 # "Here every bit corresponds to an existing port", "Devices can be attached to ports"
	version: u32
	command_completion_coalescing_control: u32
	command_completion_coalescing_ports: u32
	enclosure_management_location: u32
	enclosure_management_control: u32
	host_capability_extended: u32
	bios_handoff_control_and_status: u32
	reserved: u8[0x74]
	vendor: u8[0x60]
	ports: ControllerPort[32]
}

pack ControllerPort {
	command_list_base_address: u64
	fis_base_address: u64
	interrupt_status: u32 # "Received packages are registered here", "Some bits indicate error?"
	interrupt_enable: u32
	command_and_status: u32
	reserved_0: u32
	task_file_data: u32 # "Upon some errors, additional information can be accessed here"
	signature: u32
	sata_status: u32 # "Upon some errors, additional information can be accessed here"
	sata_control: u32
	sata_error: u32 # "Upon some errors, additional information can be accessed here"
	sata_active: u32
	command_issue: u32 # "This is used to indicate sending"
	sata_notification: u32
	fis_based_switch_control: u32
	reserved: u32[11]
	vendor: u32[4]
}

pack CommandHeader {
	# 0                       5       6                        7              8       9      10                   11         12                     16
	# | Command length in u32 | ATAPI | Write (1: H2D, 0: D2H) | Prefetchable | Reset | BIST | Clear busy upon OK | Reserved | Port multiplier port |
	flags: u16
	physical_region_descriptor_table_entry_count: u16 # "Number of entries in physical region descriptor table (PhysicalRegionDescriptorTableEntry)"
	physical_region_descriptor_bytes_transferred: u32
	command_table_descriptor_base_address: u64
	reserved: u32[4]
}

# Summary: Represents a single entry in the physical region descriptor table. This is used to describe where data should be placed.
pack PhysicalRegionDescriptorTableEntry {
	base_address: u64
	reserved: u32

	# 0                          22         31                        32
	# | Number of bytes (4M max) | Reserved | Interrupt on completion |
	configuration: u32
}

pack CommandTable {
	command: u8[64]
	atapi_command: u64[2]
	reserved: u8[0x30]

	# Offset: 0x80
	# Each command table has physical region descriptors that are used to direct data
	physical_region_descriptor_entries: PhysicalRegionDescriptorTableEntry[PHYSICAL_REGION_DESCRIPTORS_PER_COMMAND_TABLE]

	# Must be multiple of 256 bytes
}

pack CommandList {
	# Each command list has a fixed amount of command tables
	headers: CommandHeader[COMMAND_TABLES_PER_COMMAND_LIST]
}

plain Configuration {
	lists: CommandList[MAX_NUMBER_OF_PORTS]
	fis: FIS[MAX_NUMBER_OF_PORTS]
	tables: CommandTable[COMMAND_TABLES_PER_COMMAND_LIST * MAX_NUMBER_OF_PORTS]
}

# Summary: Returns the type of the device if a device is attached to the specified port
get_device_type(ports: ControllerPort*, port: u32) {
	status = ports[port].sata_status

	# Verify the port is present and active
	detection = status & 0x0F
	interface_power_management = (status |> 8) & 0x0F

	if detection != PORT_DETECTION_PRESENT or interface_power_management != PORT_INTERFACE_POWER_MANAGEMENT_ACTIVE return AHCI_DEVICE_NONE

	return when(ports[port].signature) {
		SATA_SIGNATURE_ATA => AHCI_DEVICE_SATA,
		SATA_SIGNATURE_ATAPI => AHCI_DEVICE_SATAPI,
		SATA_SIGNATURE_ENCLOSURE_MANAGEMENT_BRIDGE => AHCI_DEVICE_ENCLOSURE_MANAGEMENT_BRIDGE,
		SATA_SIGNATURE_PORT_MULTIPLIER => AHCI_DEVICE_PORT_MULTIPLIER,
		else => AHCI_DEVICE_NONE
	}
}

# Summary: Enables command processing on the specified port
start_commands(port: ControllerPort*) {
	# Wait until command lists are not being processed
	loop ((port[].command_and_status & AHCI_STATUS_COMMAND_LIST_RUNNING) != 0) {}

	# Enable command list processing and receiving of FIS packets
	port[].command_and_status |= AHCI_STATUS_COMMAND_LIST_START
	port[].command_and_status |= AHCI_STATUS_FIS_RECEIVE_ENABLE
}

# Summary: Disables command processing on the specified port
stop_commands(port: ControllerPort*) {
	# Stop command list processing
	port[].command_and_status &= !AHCI_STATUS_COMMAND_LIST_START

	# Stop receiving FIS packets
	port[].command_and_status &= !AHCI_STATUS_FIS_RECEIVE_ENABLE

	# Wait until both operations stop running
	loop {
		if (port[].command_and_status & AHCI_STATUS_COMMAND_LIST_RUNNING) != 0 continue
		if (port[].command_and_status & AHCI_STATUS_FID_RECEIVE_RUNNING) != 0 continue
		stop
	}
}

# Summary: Configures the specified port by registering its data structures
configure_port(configuration: Configuration, port: ControllerPort*, i: u32) {
	# Disable commands so that the port is not being used when we configure it
	stop_commands(port)

	# Register a command list for the specified port
	port[].command_list_base_address = configuration.lists + i * capacityof(CommandList)
	memory.zero(port[].command_list_base_address, capacityof(CommandList))

	# Register a FIS packet for the specified port
	port[].fis_base_address = configuration.fis + i * capacityof(FIS)
	memory.zero(port[].fis_base_address, capacityof(FIS))

	# Register the command tables
	headers: CommandHeader* = configuration.lists[i].headers
	tables: CommandTable* = configuration.tables + i * COMMAND_TABLES_PER_COMMAND_LIST * capacityof(CommandTable)

	loop (i = 0, i < COMMAND_TABLES_PER_COMMAND_LIST, i++) {
		# Register how many physical region descriptors there are in this table
		headers[i].physical_region_descriptor_table_entry_count = PHYSICAL_REGION_DESCRIPTORS_PER_COMMAND_TABLE

		# Register the command table
		headers[i].command_table_descriptor_base_address = tables + i * capacityof(CommandTable)
		memory.zero(headers[i].command_table_descriptor_base_address, capacityof(CommandTable))
	}

	# Enable commands, because we are done configuring
	start_commands(port)
}

# Summary: Scans the ports of the specified interface and finds attached devices
scan_ports(interface: ControllerInterface) {
	# Map the controller so it can be accessed
	mapper.map_region(interface as link, interface as link, capacityof(interface))

	debug.write('AHCI: Scanning ports: Interface=')
	debug.write_address(interface)
	debug.write(', Capabilities=')
	debug.write_address(interface.host_capability)
	debug.write_line()

	# Allocate the configuration structures
	debug.write_line('AHCI: Allocating primary configuration')
	configuration = Configuration() using KernelHeap

	# Enter AHCI aware mode
	# interface.global_host_control = 0x80000000

	# Enable PCI interrupt line

	# Enable bus mastering, so in other words the controller can initiate direct memory access (DMA) transactions.
	# This means that the controller can access the main memory independently from CPU.

	# Enable global interrupts, so that we can receive interrupts from the controller?
	interface.global_host_control = interface.global_host_control | 2

	ports = interface.ports_implemented
	i = 0

	loop (i < 32, i++) {
		# If the current bit is set, the port exists
		if ports & 1 {
			type = get_device_type(interface.ports, i)

			message = when(type) {
				AHCI_DEVICE_SATA => 'SATA',
				AHCI_DEVICE_SATAPI => 'SATAPI',
				AHCI_DEVICE_ENCLOSURE_MANAGEMENT_BRIDGE => 'Enclosure management bridge',
				AHCI_DEVICE_PORT_MULTIPLIER => 'Port multiplier',
				else => 'Nothing'
			}

			debug.write('AHCI: Port ') debug.write(i) debug.write(': ') debug.write_line(message)

			if type == AHCI_DEVICE_SATA {
				# Configure the port
				# configure_port((interface.ports + i * capacityof(ControllerPort)) as ControllerPort*)
			}
		}

		# Move to the next port
		ports = ports |> 1
	}
}

initialize(parser: kernel.acpi.Parser) {
	loop (i = 0, i < parser.device_identifiers.size, i++) {
		device = parser.device_identifiers[i]

		# Find SATA-controllers
		if device.class_code != kernel.acpi.CLASS_MASS_STORAGE_CONTROLLER or
			device.subclass_code != kernel.acpi.SUBCLASS_SATA_CONTROLLER {
			continue
		}

		scan_ports(device.bar5 as ControllerInterface)
	}
}