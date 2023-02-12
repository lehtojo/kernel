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

namespace kernel.apic

local_apic_registers: u32*

constant APIC_BASE_MSR = 0x1B
constant APIC_BASE_MSR_ENABLE = 0x800

constant ROOT_SYSTEM_DESCRIPTOR_POINTER_SIGNATURE = 'RSD PTR '

pack MADT {
	header: SDTHeader
	local_apic_address: u32
	flags: u32
}

pack MADTEntryHeader {
	type: u8
	length: u8
}

ApicInformation {
	local_apic_ids: u8[256]
	local_apic_count: u8
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
	table = mapper.map_kernel_region(physical_address, sizeof(SDTHeader)) as SDTHeader*

	# Map the whole table
	return mapper.map_kernel_region(physical_address, table[].length)
}

# Summary:
# Goes through all the RSDT tables and attempts to return the table with the specified signature.
# The returned address is a virtual address.
export find_table_from_rsdt(header: SDTHeader*, tables: u32*, signature: link): link {
	debug.write('APIC: Finding table under RSDT ')
	debug.write_address(header)
	debug.write_line()

	# Compute the number of tables in the SDT
	table_count = (header[].length - sizeof(SDTHeader)) / strideof(u32)

	# Compute the length of the signature to look for
	signature_length = length_of(signature)

	debug.write('APIC: RSDT table count: ')
	debug.write_line(table_count)

	debug.write('APIC: RSDT tables: ')

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

	debug.write('APIC: RSDP revision=')
	debug.write_line(revision as i64)

	if revision === 0 {
		rsdt: SDTHeader* = map_table(rsdp[].base.rsdt_address as link)
		tables: u32* = rsdt + sizeof(SDTHeader)

		return find_table_from_rsdt(rsdt, tables, signature)
	}

	return none as link
}

# Summary:
# Attempts to find the root system descriptor table from EBDA.
# Returns none pointer upon failure.
export find_root_system_descriptor_table() {
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
	entry = (madt + sizeof(MADT)) as MADTEntryHeader*

	loop (entry < end) {
		# Load the type of the current entry
		type = entry[].type

		if type == 0 {
			# Single logical processor with a local apic
			information.local_apic_ids[information.local_apic_count] = entry.(u8*)[3]
			information.local_apic_count++
		} else type == 1 {
			# Address of ioapic
			ioapic_registers_physical_address = (entry + 4).(u32*)[] as link
			information.ioapic_registers = mapper.map_kernel_page(ioapic_registers_physical_address)
		} else type == 5 {
			# Address of the local apic (64-bit system version)
			local_apic_registers_physical_address = (entry + 4).(u64*)[] as link
			information.local_apic_registers = mapper.map_kernel_page(local_apic_registers_physical_address)
		}

		# Move to the next entry
		entry += entry[].length
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
	ports.write_u8(0xa1, 0xff)
	ports.write_u8(0x21, 0xff)

	base = get_apic_base()
	mapper.map_kernel_page(base as link)
	set_apic_base(base)
}

export enable_interrupts(registers: u32*) {
	# Spurious Interrupt Vector Register: "Spurious interrupt usually means an interrupt whose origin is unknown"
	value = (registers + 0xF0)[]
	(registers + 0xF0)[] = value | 0x100
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

export initialize(allocator: Allocator) {
	debug.write_line('APIC: Finding root system descriptor table')

	# Find the root system descriptor table, so that we can use the hardware
	rsdp = apic.find_root_system_descriptor_table()
	debug.write('APIC: RSDP=')
	debug.write_address(rsdp as u64)
	debug.write_line()

	require(rsdp !== none, 'Failed to find rsdp')

	# Find the MADT table under RSDP
	apic_table = find_table(rsdp, 'APIC') as MADT*
	debug.write('APIC: MADT=')
	debug.write_address(apic_table as u64)
	debug.write_line()

	debug.write('APIC: Has legacy APIC: ')
	debug.write_line((apic_table[].flags & 1) != 0)

	information = ApicInformation()
	information.local_apic_registers = mapper.map_kernel_page(apic_table[].local_apic_address as link)
	process_madt_entries(apic_table, information)

	local_apic_registers = information.local_apic_registers

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
	ioapic.redirect(1, 83)
	ioapic.redirect(3, 83)
	ioapic.redirect(4, 83)

	hpet_table = find_table(rsdp, 'HPET') as hpet.HPETHeader*
	debug.write('APIC: HPET=')
	debug.write_address(hpet_table as u64)
	debug.write_line()

	if hpet_table !== none {
		hpet.initialize(allocator, hpet_table)
	}

	fadt_table = find_table(rsdp, 'FACP') as acpi.FADT
	debug.write('APIC: FADT=') debug.write_address(fadt_table as u64) debug.write_line()
	require(fadt_table !== none, 'Failed to initialize ACPI')

	mcfg_table = find_table(rsdp, 'MCFG') as acpi.MCFG
	debug.write('APIC: MCFG=') debug.write_address(mcfg_table as u64) debug.write_line()
	require(mcfg_table !== none, 'Failed to initialize MCFG')

	acpi.Parser.initialize(allocator, fadt_table, mcfg_table)

	ahci.initialize(acpi.Parser.instance)
}
