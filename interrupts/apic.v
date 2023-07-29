pack AddressStructure {
	address_space_id: u8 # 0: System memory, 1: System I/O
	register_bit_width: u8
	register_bit_offset: u8
	reserved: u8
	address: u64
}

pack RSDPDescriptor {
	signature: u64
	checksum: u8
	oem_id: char[6]
	revision: u8
	rsdt_address: u32
}

pack RSDPDescriptor20 {
	base: RSDPDescriptor
	length: u32
	xsdt_address: link
	checksum: u8
	reserved: char[3]
}

pack SDTHeader {
	signature: u32
	length: u32
	revision: u8
	checksum: u8
	oem_id: char[6]
	oem_table_id: char[8]
	oem_revision: u32
	creator_id: u32
	creator_revision: u32
}

namespace kernel.interrupts.apic

import kernel.bus

local_apic_registers: u32*
local_apic_registers_physical_address: u32*

constant APIC_BASE_MSR = 0x1B
constant APIC_BASE_MSR_ENABLE = 0x800

constant ROOT_SYSTEM_DESCRIPTOR_POINTER_SIGNATURE = 'RSD PTR '

# Can be used for causing interrupts manually. Useful for MSI and MSI-X as they write to this register to cause interrupts.
constant LOCAL_APIC_REGISTERS_INTERRUPT_COMMAND_REGISTER = 0x300

pack MADT {
	header: SDTHeader
	local_apic_address: u32
	flags: u32
}

plain MADTEntryHeader {
	type: u8
	length: u8
}

plain LocalApicEntry {
	inline header: MADTEntryHeader
	processor_id: u8
	id: u8
	flags: u32

	print(): _ {
		debug.write('Local APIC entry: ')
		debug.write('processor_id = ') debug.write(processor_id as i64)
		debug.write(', id = ') debug.write(id as i64)
		debug.write(', flags = ') debug.write_address(flags as i64)
		debug.write_line()
	}
}

plain IoApicEntry {
	inline header: MADTEntryHeader
	id: u8
	reserved: u8
	address: u32
	gsi_base: u32

	print(): _ {
		debug.write('IOAPIC entry: ')
		debug.write('id = ') debug.write(id as i64)
		debug.write(', address = ') debug.write_address(address as i64)
		debug.write(', gsi_base = ') debug.write(gsi_base as i64)
		debug.write_line()
	}
}

plain IoApicInterruptSourceOverrideEntry {
	inline header: MADTEntryHeader
	bus_source: u8
	irq_source: u8
	gsi: u32
	flags: u16

	print(): _ {
		debug.write('IOAPIC interrupt source override entry: ')
		debug.write('bus_source = ') debug.write(bus_source as i64)
		debug.write(', irq_source = ') debug.write(irq_source as i64)
		debug.write(', gsi = ') debug.write(gsi as i64)
		debug.write(', flags = ') debug.write_address(flags as i64)
		debug.write_line()
	}
}

plain IoApicNonMaskableInterruptSourceEntry {
	inline header: MADTEntryHeader
	nmi_source: u8
	reserved: u8
	flags: u16
	global_system_interrupt: u32

	print(): _ {
		debug.write('IOAPIC NMI source entry: ')
		debug.write('nmi_source = ') debug.write(nmi_source as i64)
		debug.write(', flags = ') debug.write_address(flags as i64)
		debug.write(', global_system_interrupt = ') debug.write(global_system_interrupt as i64)
		debug.write_line()
	}
}

plain LocalApicNonMaskableInterruptsEntry {
	inline header: MADTEntryHeader
	flags: u16
	lint: u8

	print(): _ {
		debug.write('Local APIC NMI entry: ')
		debug.write('flags = ') debug.write_address(flags as i64)
		debug.write(', lint = ') debug.write(lint as i64)
		debug.write_line()
	}
}

plain LocalApicAddressOverrideEntry {
	inline header: MADTEntryHeader
	reserved: u16
	address: u64

	print(): _ {
		debug.write('Local APIC address override: ')
		debug.write('address = ') debug.write_address(address as i64)
		debug.write_line()
	}
}

plain ProcessorLocalX2ApicEntry {
	inline header: MADTEntryHeader
	reserved: u16
	processor_id: u32
	flags: u32
	id: u32

	print(): _ {
		debug.write('Processor local x2 APIC: ')
		debug.write('processor_id = ') debug.write(processor_id as i64)
		debug.write(', flags = ') debug.write_address(flags as i64)
		debug.write(', id = ') debug.write(id as i64)
		debug.write_line()
	}
}

ApicInformation {
	local_apic_ids: u8[256]
	local_apic_count: u8
	local_apic_registers_physical_address: link
	local_apic_registers: link
	ioapic_registers: link
}

# Summary:
# Returns the address of the first chunk that starts with the specified signature.
# If no such chunk is found, none pointer is returned.
export find_chunk_with_signature(address: link, size: u32, signature: link, chunk_size: u32): link {
	end = address + size
	signature_length = length_of(signature)

	loop (address < end) {
		if memory.compare(address, signature, signature_length) return address
		address += chunk_size
	}

	return none as link
}

# Summary:
# Maps the specified table to a virtual address by first reading it length from its header.
export map_table(physical_address: link): link {
	# Map the header first and read the length of the table
	table = mapper.map_kernel_region(physical_address, sizeof(SDTHeader), MAP_NO_CACHE) as SDTHeader*

	# Map the whole table
	return mapper.map_kernel_region(physical_address, table[].length, MAP_NO_CACHE)
}

# Summary:
# Goes through all the RSDT tables and attempts to return the table with the specified signature.
# The returned address is a virtual address.
export find_table_with_signature(tables, table_count: u64, signature: link): link {
	debug.write('APIC: Finding table with signature starting from ')
	debug.write_address(tables)
	debug.write_line()

	# Compute the length of the signature to look for
	signature_length = length_of(signature)

	debug.write('APIC: Number of tables = ')
	debug.write_line(table_count)

	debug.write_line('APIC: Tables: ')

	# Store the table that has the specified signature
	result = none as SDTHeader*

	loop (i = 0, i < table_count, i++) {
		table = map_table(tables[i] as link)

		# Return the table if its signature matches the specified signature
		if memory.compare(table, signature, signature_length) {
			result = table
		}

		debug.write('APIC: Found table with signature ')
		debug.write(table, strideof(i32))
		debug.write_line()
	}

	return result
}

# Summary:
# Attempts to find a system descriptor table with the specified signature under the specified RSDP.
# Returns none pointer upon failure.
export find_table(rsdp: RSDPDescriptor20*, signature: link): link {
	revision = rsdp[].base.revision

	debug.write('APIC: RSDP revision = ')
	debug.write_line(revision as i64)

	if revision === 0 {
		rsdt = map_table(rsdp[].base.rsdt_address as link) as SDTHeader*
		tables: u32* = (rsdt as link) + sizeof(SDTHeader)
		table_count = (rsdt[].length - sizeof(SDTHeader)) / sizeof(u32)

		return find_table_with_signature(tables, table_count, signature)
	}

	if revision === 2 {
		xsdt = map_table(rsdp[].xsdt_address as link) as SDTHeader*
		tables: u64* = (xsdt as link) + sizeof(SDTHeader)
		table_count = (xsdt[].length - sizeof(SDTHeader)) / sizeof(u64)
		return find_table_with_signature(tables, table_count, signature)
	}

	return none as link
}

# Summary:
# Attempts to find the RSDP from the specified UEFI information.
# Panics upon failure.
export find_root_system_descriptor_table_from_uefi_uefi_information(uefi_information: UefiInformation) {
	debug.write_line('APIC: Finding RSDP 2.0 using UEFI information...')

	configuration_table = uefi_information.system_table.configuration_table
	number_of_table_entries = uefi_information.system_table.number_of_table_entries

	debug.write('APIC: Number of configuration table entries = ') debug.write_line(number_of_table_entries)

	rsdp_guid = UefiGuid.new(0x8868e871, 0xe4f1, 0x11d3, 0xbc, 0x22, 0x00, 0x80, 0xc7, 0x3c, 0x88, 0x81)

	loop (i = 0, i < number_of_table_entries, i++) {
		if configuration_table[i].vendor_guid != rsdp_guid continue

		rsdp = configuration_table[i].vendor_table
		debug.write('APIC: Found RSDP 2.0 at physical address ')
		debug.write_address(rsdp)
		debug.write_line()

		return mapper.to_kernel_virtual_address(rsdp)
	}

	panic('APIC: Failed to find RSDP 2.0')
}

# Summary:
# Attempts to find the root system descriptor table from EBDA.
# Returns none pointer upon failure.
export find_root_system_descriptor_table(uefi_information: UefiInformation) {
	if uefi_information !== none {
		return find_root_system_descriptor_table_from_uefi_uefi_information(uefi_information)
	}

	# EBDA = Extended BIOS Data Area
	# RSDP = Root system descriptor pointer
	ebda_segment_pointer = mapper.to_kernel_virtual_address(0x40E) as u16*
	ebda_page_address = mapper.to_kernel_virtual_address((ebda_segment_pointer[] <| 4) as link)

	# Size of the EBDA is stored in the first byte of the area (1K units)
	ebda_size = ebda_page_address[] * KiB

	# Try finding RSDP from EBDA
	rsdp = find_chunk_with_signature(ebda_page_address, ebda_size, ROOT_SYSTEM_DESCRIPTOR_POINTER_SIGNATURE, 16)
	if rsdp !== none return rsdp

	# Store the location and size of BIOS area
	bios_page_address = mapper.to_kernel_virtual_address(0xE0000) as u8*
	bios_size = 128 * KiB

	# Try finding RSDP from EBDA
	rsdp = find_chunk_with_signature(bios_page_address, bios_size, ROOT_SYSTEM_DESCRIPTOR_POINTER_SIGNATURE, 16)
	if rsdp !== none return rsdp

	return none as link
}

export process_madt_entries(madt: MADT*, information: ApicInformation) {
	# Compute the end address of the specified table, so we know when to stop
	end = madt + madt[].header.length
	entry = (madt + sizeof(MADT)) as MADTEntryHeader

	loop (entry < end) {
		# Load the type of the current entry
		type = entry.type

		if type == 0 {
			local_apic_entry = entry as LocalApicEntry
			# local_apic_entry.print() # Todo: Enable

			# Single logical processor with a local apic
			information.local_apic_ids[information.local_apic_count] = local_apic_entry.id
			information.local_apic_count++
		} else type == 1 {
			ioapic_entry = entry as IoApicEntry
			ioapic_entry.print()

			# Todo: Support multiple IOAPICs as you can not do everything with one
			if information.ioapic_registers === none {
				information.ioapic_registers = mapper.map_kernel_page(ioapic_entry.address as link, MAP_NO_CACHE)
			}
		} else type == 2 {
			ioapic_interrupt_source_override_entry = entry as IoApicInterruptSourceOverrideEntry
			ioapic_interrupt_source_override_entry.print()
		} else type == 3 {
			ioapic_nmi_source_entry = entry as IoApicNonMaskableInterruptSourceEntry
			# ioapic_nmi_source_entry.print() # Todo: Enable
		} else type == 4 {
			local_apic_nmi_entry = entry as LocalApicNonMaskableInterruptsEntry
			# local_apic_nmi_entry.print() # Todo: Enable
		} else type == 5 {
			local_apic_address_override_entry = entry as LocalApicAddressOverrideEntry
			local_apic_address_override_entry.print()
	
			information.local_apic_registers_physical_address = local_apic_address_override_entry.address as link
			information.local_apic_registers = mapper.map_kernel_page(information.local_apic_registers_physical_address, MAP_NO_CACHE)
		} else type == 9 {
			processor_local_x2apic_entry = entry as ProcessorLocalX2ApicEntry
			processor_local_x2apic_entry.print()
		}

		# Move to the next entry
		entry += entry.length
	}
}

# Summary: Sets the physical address of local APIC registers.
export set_apic_base(base: u64) {
	value = (base & 0xfffff0000) | APIC_BASE_MSR_ENABLE
	write_msr(APIC_BASE_MSR, value)
}

# Summary: Returns the physical address of local APIC registers.
export get_apic_base(): u64 {
	value = read_msr(APIC_BASE_MSR)
	return value & 0xffffff000
}

export enable() {
	# Disable 8259 PIC:
	# mov al, 0xff
	# out 0xa1, al
	# out 0x21, al
	debug.write_line('APIC: Disabling 8259 PIC...')
	ports.write_u8(0xa1, 0xff)
	ports.write_u8(0x21, 0xff)

	debug.write_line('APIC: Enabling IOAPIC...')
	base = get_apic_base()
	mapper.map_kernel_page(base as link, MAP_NO_CACHE)
	set_apic_base(base)
}

export enable_interrupts(registers: u32*) {
	# Spurious Interrupt Vector Register: "Spurious interrupt usually means an interrupt whose origin is unknown"
	spurious_interrupt = 0xff

	value = (registers + 0xf0)[]
	value |= spurious_interrupt # Map spurious interrupts
	value |= 0x100 # Enable APIC
	(registers + 0xf0)[] = value
}

# Summary:
# Returns the number of possible interrupt redirections based on the specified IOAPIC registers.
export max_redirection(registers: u32*) {
	# Index: 1
	# 32-bit read
	# Shift left 16

	# Select the register by writing it to IOREGSEL
	registers[] = 1

	# Read the result
	result = (registers + 0x10)[]

	return result |> 16
}

export initialize(allocator: Allocator, uefi_information: UefiInformation) {
	debug.write_line('APIC: Finding root system descriptor table')

	# Find the root system descriptor table, so that we can use the hardware
	rsdp = find_root_system_descriptor_table(uefi_information)
	debug.write('APIC: RSDP=')
	debug.write_address(rsdp as u64)
	debug.write_line()

	require(rsdp !== none, 'Failed to find rsdp')

	# Find the MADT table under RSDP
	apic_table = find_table(rsdp, 'APIC') as MADT*
	require(apic_table !== none, 'Failed to find MADT')

	debug.write('APIC: MADT = ')
	debug.write_address(apic_table as u64)
	debug.write_line()

	debug.write('APIC: 8259 PIC = ')
	debug.write_line((apic_table[].flags & 1) != 0)

	information = ApicInformation()
	information.ioapic_registers = none as link
	information.local_apic_registers_physical_address = apic_table[].local_apic_address as link
	information.local_apic_registers = mapper.map_kernel_page(information.local_apic_registers_physical_address, MAP_NO_CACHE)
	process_madt_entries(apic_table, information)

	local_apic_registers_physical_address = information.local_apic_registers_physical_address
	local_apic_registers = information.local_apic_registers

	debug.write('APIC: Local APIC registers physical address = ')
	debug.write_address(information.local_apic_registers_physical_address)
	debug.write_line()

	debug.write('APIC: Local APIC Registers = ')
	debug.write_address(information.local_apic_registers)
	debug.write_line()

	debug.write('APIC: IOAPIC Registers = ')
	debug.write_address(information.ioapic_registers)
	debug.write_line()

	debug.write('APIC: Max redirections = ')
	debug.write_line(max_redirection(information.ioapic_registers))

	debug.write('APIC: Processors: ')

	loop (i = 0, i < information.local_apic_count, i++) {
		debug.write(information.local_apic_ids[i])
		debug.put(` `)
	}

	debug.write_line()

	enable()
	enable_interrupts(information.local_apic_registers)

	ioapic.initialize(information.ioapic_registers)

	# Enable PS/2 keyboard
	ioapic.redirect(1, 0) # Todo: CPU id?

	# Todo: Remove
	# ioapic.redirect(3, 0)
	# ioapic.redirect(4, 0)

	hpet_table = find_table(rsdp, 'HPET') as hpet.HPETHeader*
	debug.write('APIC: HPET = ')
	debug.write_address(hpet_table as u64)
	debug.write_line()

	if hpet_table !== none {
		hpet.initialize(allocator, hpet_table)
	}

	fadt_table = find_table(rsdp, 'FACP') as acpi.FADT
	debug.write('APIC: FADT = ') debug.write_address(fadt_table as u64) debug.write_line()
	require(fadt_table !== none, 'Failed to initialize ACPI')

	mcfg_table = find_table(rsdp, 'MCFG') as acpi.MCFG
	debug.write('APIC: MCFG = ') debug.write_address(mcfg_table as u64) debug.write_line()
	require(mcfg_table !== none, 'Failed to initialize MCFG')

	pci.initialize()
	acpi.Parser.initialize(allocator, fadt_table, mcfg_table)

	# ahci.initialize(acpi.Parser.instance)
}
