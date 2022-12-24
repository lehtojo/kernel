# ACPI (Advanced Configuration and Power Interface)
namespace kernel.acpi

plain FADT {
	header: SDTHeader
	firmware_ctrl: u32
	dsdt_ptr: u32
	reserved: u8
	preferred_pm_profile: u8
	sci_int: u16
	smi_cmd: u32
	acpi_enable_value: u8
	acpi_disable_value: u8
	s4bios_req: u8
	pstate_cnt: u8
	PM1a_EVT_BLK: u32
	PM1b_EVT_BLK: u32
	PM1a_CNT_BLK: u32
	PM1b_CNT_BLK: u32
	PM2_CNT_BLK: u32
	PM_TMR_BLK: u32
	GPE0_BLK: u32
	GPE1_BLK: u32
	PM1_EVT_LEN: u8
	PM1_CNT_LEN: u8
	PM2_CNT_LEN: u8
	PM_TMR_LEN: u8
	GPE0_BLK_LEN: u8
	GPE1_BLK_LEN: u8
	GPE1_BASE: u8
	cst_cnt: u8
	P_LVL2_LAT: u16
	P_LVL3_LAT: u16
	flush_size: u16
	flush_stride: u16
	duty_offset: u8
	duty_width: u8
	day_alrm: u8
	mon_alrm: u8
	century: u8
	ia_pc_boot_arch_flags: u16
	reserved2: u8
	flags: u32
	reset_reg: AddressStructure
	reset_value: u8
	arm_boot_arch: u16
	fadt_minor_version: u8
	x_firmware_ctrl: u64
	x_dsdt: u64
	x_pm1a_evt_blk: AddressStructure
	x_pm1b_evt_blk: AddressStructure
	x_pm1a_cnt_blk: AddressStructure
	x_pm1b_cnt_blk: AddressStructure
	x_pm2_cnt_blk: AddressStructure
	x_pm_tmr_blk: AddressStructure
	x_gpe0_blk: AddressStructure
	x_gpe1_blk: AddressStructure
	sleep_control: AddressStructure
	sleep_status: AddressStructure
	hypervisor_vendor_identity: u64
}

pack MemoryMapDescriptor {
	base_address: u64
	segment_group_number: u16
	start_pci_bus: u8
	end_pci_bus: u8
	reserved: u32
}

plain MCFG {
	header: SDTHeader
	reserved: u64
}

pack HardwareInformation {
	wbinvd: bool
	wbinvd_flush: bool
	processor_c1: bool
	multiprocessor_c2: bool
	power_button: bool
	sleep_button: bool
	fix_rtc: bool
	rtc_s4: bool
	timer_value_extension: bool
	docking_capability: bool
	reset_register_supported: bool
	sealed_case: bool
	headless: bool
	cpu_software_sleep: bool
	pci_express_wake: bool
	use_platform_clock: bool
	s4_rtc_status_valid: bool
	remote_power_on_capable: bool
	force_apic_cluster_model: bool
	force_apic_physical_destination_mode: bool
	hardware_reduced_acpi: bool
	low_power_s0_idle_capable: bool
}

pack HardwareInformationx86 {
	legacy_devices: bool
	keyboard_8042: bool
	vga_not_present: bool
	msi_not_supported: bool
	cmos_rtc_not_present: bool
}

pack Domain {
	id: u32
	start: u8
	end: u8

	shared new(id: u32, start: u8, end: u8) {
		return pack { id: id, start: start, end: end } as Domain
	}
}

pack HardwareId {
	vendor: u16
	device: u16

	shared new(vendor: u16, device: u16): HardwareId {
		return pack { vendor: vendor, device: device } as HardwareId
	}
}

pack Capability {
	address: link
	id: u8
	pointer: u8

	shared new(address: link, id: u8, pointer: u8): Capability {
		return pack { address: address, id: id, pointer: pointer } as Capability
	}
}

plain DeviceIdentifier {
	address: link
	id: HardwareId
	revision_id: u8
	class_code: u8
	subclass_code: u8
	programming_interface: u8
	bar0: u32
	bar1: u32
	bar2: u32
	bar3: u32
	bar4: u32
	bar5: u32
	subsystem_id: u16
	subsystem_vendor_id: u16
	interrupt_pin: u8
	interrupt_line: u8

	init(address: link, id: HardwareId, revision_id: u8, class_code: u8, subclass_code: u8, programming_interface: u8, bar0: u32, bar1: u32, bar2: u32, bar3: u32, bar4: u32, bar5: u32, subsystem_id: u16, subsystem_vendor_id: u16, interrupt_pin: u8, interrupt_line: u8) {
		this.address = address
		this.id = id
		this.revision_id = revision_id
		this.class_code = class_code
		this.subclass_code = subclass_code
		this.programming_interface = programming_interface
		this.bar0 = bar0
		this.bar1 = bar1
		this.bar2 = bar2
		this.bar3 = bar3
		this.bar4 = bar4
		this.bar5 = bar5
		this.subsystem_id = subsystem_id
		this.subsystem_vendor_id = subsystem_vendor_id
		this.interrupt_pin = interrupt_pin
		this.interrupt_line = interrupt_line
	}
}

plain HostController {
	domain: Domain
	address: link
	mapped_bus: i16
	mapped_bus_address: link

	init(domain: Domain, address: link) {
		this.domain = domain
		this.address = address
		this.mapped_bus = -1
		this.mapped_bus_address = 0
	}

	map_bus_region(bus: u8) {
		if mapped_bus == bus return

		debug.write('PCI: Mapping bus ') debug.write(bus) debug.write(' in domain ') debug.write_line(domain.id)
		start_bus = math.min(bus, domain.start)

		mapped_bus = bus
		mapped_bus_address = address + MEMORY_RANGE_PER_BUS * (bus - start_bus)

		mapper.map_region(mapped_bus_address, mapped_bus_address, MEMORY_RANGE_PER_BUS)
	}

	compute_function_address(bus: u8, device: u8, function: u8, register: u8): link {
		map_bus_region(bus)
		return mapped_bus_address + DEVICE_SPACE_SIZE * function + (DEVICE_SPACE_SIZE * MAX_FUNCTIONS_PER_DEVICE) * device + (register & 0xfff)
	}

	read_u8(bus: u8, device: u8, function: u8, register: u8): u8 {
		return compute_function_address(bus, device, function, register).(u8*)[]
	}

	read_u16(bus: u8, device: u8, function: u8, register: u8): u16 {
		return compute_function_address(bus, device, function, register).(u16*)[]
	}

	read_u32(bus: u8, device: u8, function: u8, register: u8): u32 {
		return compute_function_address(bus, device, function, register).(u32*)[]
	}

	print_device(id: HardwareId, class: u8, subclass: u8) {
		debug.write('PCI Device: Vendor Id=')
		debug.write_address(id.vendor)
		debug.write(', Device Id=')
		debug.write_address(id.device)
		debug.write(', Type: ')

		if class == CLASS_MASS_STORAGE_CONTROLLER {
			debug.write('Mass storage device')
			if subclass == SUBCLASS_SATA_CONTROLLER debug.write(', SATA Controller')
			if subclass == SUBCLASS_NVMHCI_CONTROLLER debug.write(', NVMHCI Controller')
			if subclass == SUBCLASS_NVME_CONTROLLER debug.write(', NVME Controller')
			debug.write_line()
			return
		}
		if class == CLASS_NETWORK_CONTROLLER {
			debug.write('Network controller')
			if subclass == SUBCLASS_ETHERNET_CONTROLLER debug.write(', Ethernet Controller')
			debug.write_line()
			return
		}
		if class == CLASS_DISPLAY_CONTROLLER {
			debug.write('Display controller')
			if subclass == SUBCLASS_VGA_CONTROLLER debug.write(', VGA Controller')
			if subclass == SUBCLASS_XGA_CONTROLLER debug.write(', XGA Controller')
			if subclass == SUBCLASS_3D_CONTROLLER debug.write(', 3D Controller')
			debug.write_line()
			return
		}
		if class == CLASS_BRIDGE {
			debug.write('Bridge')
			if subclass == SUBCLASS_PCI_TO_PCI debug.write(', PCI-to-PCI')
			debug.write_line()
			return
		}
		if class == CLASS_BASE_SYSTEM_PERIPHERAL {
			debug.write('Base system peripheral')
			if subclass == SUBCLASS_PIC debug.write(', PIC')
			if subclass == SUBCLASS_DMA_CONTROLLER debug.write(', DMA Controller')
			if subclass == SUBCLASS_TIMER debug.write(', Timer')
			if subclass == SUBCLASS_RTC_CONTROLLER debug.write(', RTC Controller')
			debug.write_line()
			return
		}
		if class == CLASS_INPUT_DEVICE_CONTROLLER {
			debug.write('Input device controller')
			if subclass == SUBCLASS_KEYBOARD_CONTROLLER debug.write(', Keyboard Controller')
			if subclass == SUBCLASS_MOUSE_CONTROLLER debug.write(', Mouse Controller')
			debug.write_line()
			return
		}
		if class == CLASS_SERIAL_BUS_CONTROLLER {
			debug.write('Serial bus controller')
			if subclass == SUBCLASS_USB_CONTROLLER debug.write(', USB Controller')
			debug.write_line()
			return
		}
		if class == CLASS_WIRELESS_CONTROLLER {
			debug.write('Wireless controller')
			if subclass == SUBCLASS_BLUETOOTH_CONTROLLER debug.write(', Bluetooth Controller')
			if subclass == SUBCLASS_BROADBAND_CONTROLLER debug.write(', Broadband Controller')
			if subclass == SUBCLASS_ETHERNET_CONTROLLER_802_1A debug.write(', Ethernet Controller (802.1a)')
			if subclass == SUBCLASS_ETHERNET_CONTROLLER_802_1B debug.write(', Ethernet Controller (802.1b)')
			debug.write_line()
			return
		}

		debug.write(class) debug.put(`.`) debug.write_line(subclass)
	}

	scan_function(bus: u8, device: u8, function: u8, devices: List<DeviceIdentifier>) {
		id = HardwareId.new(read_u16(bus, device, function, REGISTER_VENDOR_ID), read_u16(bus, device, function, REGISTER_DEVICE_ID))
		revision_id = read_u8(bus, device, function, REGISTER_REVISION_ID)
		class_code = read_u8(bus, device, function, REGISTER_CLASS)
		subclass_code = read_u8(bus, device, function, REGISTER_SUBCLASS)
		programming_interface = read_u8(bus, device, function, REGISTER_PROGRAMMING_INTERFACE)
		bar0 = read_u32(bus, device, function, REGISTER_BAR0)
		bar1 = read_u32(bus, device, function, REGISTER_BAR1)
		bar2 = read_u32(bus, device, function, REGISTER_BAR2)
		bar3 = read_u32(bus, device, function, REGISTER_BAR3)
		bar4 = read_u32(bus, device, function, REGISTER_BAR4)
		bar5 = read_u32(bus, device, function, REGISTER_BAR5)
		subsystem_id = read_u16(bus, device, function, REGISTER_SUBSYSTEM_ID)
		subsystem_vendor_id = read_u16(bus, device, function, REGISTER_SUBSYSTEM_VENDOR_ID)
		interrupt_pin = read_u8(bus, device, function, REGISTER_INTERRUPT_PIN)
		interrupt_line = read_u8(bus, device, function, REGISTER_INTERRUPT_LINE)

		devices.add(DeviceIdentifier(
			none as link, id, revision_id,
			class_code, subclass_code,
			programming_interface,
			bar0, bar1, bar2, bar3, bar4, bar5,
			subsystem_id, subsystem_vendor_id,
			interrupt_pin, interrupt_line
		) using devices.allocator)

		print_device(id, class_code, subclass_code)
	}

	scan_device(bus: u8, device: u8, devices: List<DeviceIdentifier>) {
		if read_u16(bus, device, 0, REGISTER_VENDOR_ID) == PCI_NONE return
		scan_function(bus, device, 0, devices)

		# If the last bit of the header type is set, then the this device has multiple functions
		header_type = read_u8(bus, device, 0, REGISTER_HEADER_TYPE)
		if (header_type & 0x80) == 0 return

		# Scan the functions of this device
		loop (function = 1, function < MAX_FUNCTIONS_PER_DEVICE, function++) {
			if read_u16(bus, device, function, REGISTER_VENDOR_ID) == PCI_NONE continue
			scan_function(bus, device, function, devices)
		}
	}

	scan_bus(bus: u8, devices: List<DeviceIdentifier>) {
		loop (device = 0, device < MAX_DEVICES_PER_BUS, device++) {
			scan_device(bus, device, devices)
		}
	}

	scan(devices: List<DeviceIdentifier>) {
		header_type = read_u16(0, 0, 0, REGISTER_HEADER_TYPE)

		# If the last bit of the header type is set, then there are multiple PCI host controllers
		if (header_type & 0x80) == 0 {
			scan_bus(0, devices)
		} else {
			loop (function = 0, function < MAX_FUNCTIONS_PER_DEVICE, function++) {
				if read_u16(0, 0, function, REGISTER_VENDOR_ID) != PCI_NONE stop
				scan_bus(function, devices)
			}
		}
	}
}

constant FEATURE_WBINVD = 1 <| 0
constant FEATURE_WBINVD_FLUSH = 1 <| 1
constant FEATURE_PROC_C1 = 1 <| 2
constant FEATURE_P_LVL2_UP = 1 <| 3
constant FEATURE_PWR_BUTTON = 1 <| 4
constant FEATURE_SLP_BUTTON = 1 <| 5
constant FEATURE_FIX_RTC = 1 <| 6
constant FEATURE_RTC_s4 = 1 <| 7
constant FEATURE_TMR_VAL_EXT = 1 <| 8
constant FEATURE_DCK_CAP = 1 <| 9
constant FEATURE_RESET_REG_SUPPORTED = 1 <| 10
constant FEATURE_SEALED_CASE = 1 <| 11
constant FEATURE_HEADLESS = 1 <| 12
constant FEATURE_CPU_SW_SLP = 1 <| 13
constant FEATURE_PCI_EXP_WAK = 1 <| 14
constant FEATURE_USE_PLATFORM_CLOCK = 1 <| 15
constant FEATURE_S4_RTC_STS_VALID = 1 <| 16
constant FEATURE_REMOTE_POWER_ON_CAPABLE = 1 <| 17
constant FEATURE_FORCE_APIC_CLUSTER_MODEL = 1 <| 18
constant FEATURE_FORCE_APIC_PHYSICAL_DESTINATION_MODE = 1 <| 19
constant FEATURE_HW_REDUCED_ACPI = 1 <| 20
constant FEATURE_LOW_POWER_S0_IDLE_CAPABLE = 1 <| 21

constant IA_PC_FLAGS_Legacy_Devices = 1 <| 0
constant IA_PC_FLAGS_PS2_8042 = 1 <| 1
constant IA_PC_FLAGS_VGA_Not_Present = 1 <| 2
constant IA_PC_FLAGS_MSI_Not_Supported = 1 <| 3
constant IA_PC_FLAGS_PCIe_ASPM_Controls = 1 <| 4
constant IA_PC_FLAGS_CMOS_RTC_Not_Present = 1 <| 5

constant REGISTER_VENDOR_ID = 0x00
constant REGISTER_DEVICE_ID = 0x02
constant REGISTER_COMMAND = 0x04
constant REGISTER_STATUS = 0x06
constant REGISTER_REVISION_ID = 0x08
constant REGISTER_PROGRAMMING_INTERFACE = 0x09
constant REGISTER_SUBCLASS = 0x0a
constant REGISTER_CLASS = 0x0b
constant REGISTER_CACHE_LINE_SIZE = 0x0c
constant REGISTER_LATENCY_TIMER = 0x0d
constant REGISTER_HEADER_TYPE = 0x0e
constant REGISTER_BIST = 0x0f
constant REGISTER_BAR0 = 0x10
constant REGISTER_BAR1 = 0x14
constant REGISTER_BAR2 = 0x18
constant REGISTER_SECONDARY_BUS = 0x19
constant REGISTER_BAR3 = 0x1C
constant REGISTER_BAR4 = 0x20
constant REGISTER_BAR5 = 0x24
constant REGISTER_SUBSYSTEM_VENDOR_ID = 0x2C
constant REGISTER_SUBSYSTEM_ID = 0x2E
constant REGISTER_CAPABILITIES_POINTER = 0x34
constant REGISTER_INTERRUPT_LINE = 0x3C
constant REGISTER_INTERRUPT_PIN = 0x3D

constant CLASS_MASS_STORAGE_CONTROLLER = 0x1
constant CLASS_NETWORK_CONTROLLER = 0x2
constant CLASS_DISPLAY_CONTROLLER = 0x3
constant CLASS_MULTIMEDIA_CONTROLLER = 0x4
constant CLASS_MEMORY_CONTROLLER = 0x5
constant CLASS_BRIDGE = 0x6
constant CLASS_SIMPLE_COMMUNICATION_CONTROLLER = 0x7
constant CLASS_BASE_SYSTEM_PERIPHERAL = 0x8
constant CLASS_INPUT_DEVICE_CONTROLLER = 0x9
constant CLASS_PROCESSOR = 0xB
constant CLASS_SERIAL_BUS_CONTROLLER = 0xC
constant CLASS_WIRELESS_CONTROLLER = 0xD

# CLASS_MASS_STORAGE_CONTROLLER:
constant SUBCLASS_SATA_CONTROLLER = 0x6
constant SUBCLASS_NVMHCI_CONTROLLER = 0x8
constant SUBCLASS_NVME_CONTROLLER = 0x8
# CLASS_NETWORK_CONTROLLER:
constant SUBCLASS_ETHERNET_CONTROLLER = 0x0
# CLASS_DISPLAY_CONTROLLER:
constant SUBCLASS_VGA_CONTROLLER = 0x0
constant SUBCLASS_XGA_CONTROLLER = 0x1
constant SUBCLASS_3D_CONTROLLER = 0x2
# CLASS_BRIDGE:
constant SUBCLASS_PCI_TO_PCI = 0x4
# CLASS_BASE_SYSTEM_PERIPHERAL:
constant SUBCLASS_PIC = 0x0
constant SUBCLASS_DMA_CONTROLLER = 0x1
constant SUBCLASS_TIMER = 0x2
constant SUBCLASS_RTC_CONTROLLER = 0x3
# CLASS_INPUT_DEVICE_CONTROLLER:
constant SUBCLASS_KEYBOARD_CONTROLLER = 0x0
constant SUBCLASS_MOUSE_CONTROLLER = 0x2
# CLASS_SERIAL_BUS_CONTROLLER:
constant SUBCLASS_USB_CONTROLLER = 0x3
# CLASS_WIRELESS_CONTROLLER:
constant SUBCLASS_BLUETOOTH_CONTROLLER = 0x11
constant SUBCLASS_BROADBAND_CONTROLLER = 0x12
constant SUBCLASS_ETHERNET_CONTROLLER_802_1A = 0x20
constant SUBCLASS_ETHERNET_CONTROLLER_802_1B = 0x21

constant PCI_NONE = 0xffff

constant DEVICE_SPACE_SIZE = 0x1000
constant MAX_FUNCTIONS_PER_DEVICE = 8
constant MAX_DEVICES_PER_BUS = 32
constant MEMORY_RANGE_PER_BUS = DEVICE_SPACE_SIZE * MAX_FUNCTIONS_PER_DEVICE * MAX_DEVICES_PER_BUS 

plain Parser {
	shared instance: Parser

	shared initialize(allocator: Allocator, fadt: FADT, mcfg: MCFG) {
		instance = Parser(allocator, fadt, mcfg) using allocator
	}

	allocator: Allocator

	hardware_information_x86: HardwareInformationx86
	hardware_information: HardwareInformation

	host_controllers: List<HostController>
	device_identifiers: List<DeviceIdentifier>

	init(allocator: Allocator, fadt: FADT, mcfg: MCFG) {
		this.allocator = allocator
		this.host_controllers = List<HostController>(allocator) using allocator
		this.device_identifiers = List<DeviceIdentifier>(allocator) using allocator

		process_fadt(fadt)
		process_mcfg(mcfg)
		scan()
	}

	process_fadt(fadt: FADT) {
		debug.write_line('ACPI: Processing FADT')
		debug.write('ACPI: FADT revision=') debug.write(fadt.header.revision) debug.write(', size: ') debug.write_line(fadt.header.length)

		hardware_information_x86.cmos_rtc_not_present = fadt.ia_pc_boot_arch_flags & IA_PC_FLAGS_CMOS_RTC_Not_Present
		hardware_information_x86.keyboard_8042 = (fadt.header.revision <= 3) or (fadt.ia_pc_boot_arch_flags & IA_PC_FLAGS_PS2_8042)
		hardware_information_x86.legacy_devices = fadt.ia_pc_boot_arch_flags & IA_PC_FLAGS_Legacy_Devices
		hardware_information_x86.msi_not_supported = fadt.ia_pc_boot_arch_flags & IA_PC_FLAGS_MSI_Not_Supported
		hardware_information_x86.vga_not_present = fadt.ia_pc_boot_arch_flags & IA_PC_FLAGS_VGA_Not_Present

		hardware_information.cpu_software_sleep = fadt.flags & FEATURE_CPU_SW_SLP
		hardware_information.docking_capability = fadt.flags & FEATURE_DCK_CAP
		hardware_information.fix_rtc = fadt.flags & FEATURE_FIX_RTC
		hardware_information.force_apic_cluster_model = fadt.flags & FEATURE_FORCE_APIC_CLUSTER_MODEL
		hardware_information.force_apic_physical_destination_mode = fadt.flags & FEATURE_FORCE_APIC_PHYSICAL_DESTINATION_MODE
		hardware_information.hardware_reduced_acpi = fadt.flags & FEATURE_HW_REDUCED_ACPI
		hardware_information.headless = fadt.flags & FEATURE_HEADLESS
		hardware_information.low_power_s0_idle_capable = fadt.flags & FEATURE_LOW_POWER_S0_IDLE_CAPABLE
		hardware_information.multiprocessor_c2 = fadt.flags & FEATURE_P_LVL2_UP
		hardware_information.pci_express_wake = fadt.flags & FEATURE_PCI_EXP_WAK
		hardware_information.power_button = fadt.flags & FEATURE_PWR_BUTTON
		hardware_information.processor_c1 = fadt.flags & FEATURE_PROC_C1
		hardware_information.remote_power_on_capable = fadt.flags & FEATURE_REMOTE_POWER_ON_CAPABLE
		hardware_information.reset_register_supported = fadt.flags & FEATURE_RESET_REG_SUPPORTED
		hardware_information.rtc_s4 = fadt.flags & FEATURE_RTC_s4
		hardware_information.s4_rtc_status_valid = fadt.flags & FEATURE_S4_RTC_STS_VALID
		hardware_information.sealed_case = fadt.flags & FEATURE_SEALED_CASE
		hardware_information.sleep_button = fadt.flags & FEATURE_SLP_BUTTON
		hardware_information.timer_value_extension = fadt.flags & FEATURE_TMR_VAL_EXT
		hardware_information.use_platform_clock = fadt.flags & FEATURE_USE_PLATFORM_CLOCK
		hardware_information.wbinvd = fadt.flags & FEATURE_WBINVD
		hardware_information.wbinvd_flush = fadt.flags & FEATURE_WBINVD_FLUSH
	}

	process_mcfg(mcfg: MCFG) {
		debug.write_line('ACPI: Processing MCFG')
		debug.write('ACPI: MCFG revision=') debug.write(mcfg.header.revision) debug.write(', size: ') debug.write_line(mcfg.header.length)

		# TODO: Some implementations check for overflows and abort upon failure, but why is this needed?
	
		# Map the table so that it can be accessed
		mapper.map_region(mcfg as link, mcfg as link, mcfg.header.length)

		# Compute how many memory map descriptors there are
		descriptor_count = (mcfg.header.length - sizeof(MCFG)) / sizeof(MemoryMapDescriptor)
		descriptors = (mcfg as link + sizeof(MCFG)) as MemoryMapDescriptor*
	
		# Register all of the memory mapped IOs
		loop (i = 0, i < descriptor_count, i++) {
			descriptor = descriptors[i]

			debug.write('PCI: Host controller at ')
			debug.write_address(descriptor.base_address)
			debug.write(', PCI buses ')
			debug.write(descriptor.start_pci_bus)
			debug.put(`-`)
			debug.write_line(descriptor.end_pci_bus)

			domain = Domain.new(i, descriptor.start_pci_bus, descriptor.end_pci_bus)
			host_controllers.add(HostController(domain, descriptor.base_address as link) using allocator)
		}
	}

	scan() {
		loop (i = 0, i < host_controllers.size, i++) {
			host_controllers[i].scan(device_identifiers)
		}
	}
}

