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

namespace apic

local_apic_registers: u32*

# Summary: Reads the contents of a 64-bit model specific register specified by the id
import 'C' read_msr(id: u64): u64
import 'C' write_msr(id: u64, value: u64)

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

pack SystemInformation {
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

export find_table_from_rsdt(header: SDTHeader*, tables: u32*, signature: link): link {
	allocator.map_page(header, header)
	allocator.map_page(header + 0x1000, header + 0x1000)

	debug.write('rsdt: ')
	debug.write_address(header)
	debug.write_line()

	table_count = (header[].length - capacityof(SDTHeader)) / sizeof(u32)
	signature_length = length_of(signature)

	debug.write('rsdt-table-count: ')
	debug.write_line(table_count)

	debug.write('rsdt-tables: ')

	result = none as link

	loop (i = 0, i < table_count, i++) {
		table = tables[i] as link
		allocator.map_page(table, table)

		if memory.compare(table, signature, signature_length) {
			result = table
		}

		debug.write(table, sizeof(i32))
		debug.put(` `)
	}

	debug.write_line()

	return result
}

export find_table(rsdp: RSDPDescriptor20*, signature: link): link {
	revision = rsdp[].base.revision

	debug.write('rsdp-revision: ')
	debug.write_line(revision as i64)

	if revision === 0 {
		rsdt: SDTHeader* = rsdp[].base.rsdt_address
		tables: u32* = rsdt + capacityof(SDTHeader)

		return find_table_from_rsdt(rsdt, tables, signature)
	}

	return none as link
}

export find_root_system_descriptor_table() {
	# TODO: Should we copy the data areas below?

	# EBDA = Extended BIOS Data Area
	# RSDP = Root system descriptor pointer
	ebda_segment_pointer = 0x40E as u16*
	ebda_page_address = (ebda_segment_pointer[] <| 4) as link

	# Size of the EBDA is stored in the first byte of the area (1K units)
	ebda_size = ebda_page_address[] * KiB

	# Try finding RSDP from EBDA
	rsdp = find_chunk_with_signature(ebda_page_address, ebda_size, ROOT_SYSTEM_DESCRIPTOR_POINTER_SIGNATURE, 16)
	if rsdp !== none return rsdp

	# Store the location and size of BIOS area
	bios_page_address = 0xE0000 as u8*
	bios_size = 128 * KiB

	# Try finding RSDP from EBDA
	rsdp = find_chunk_with_signature(bios_page_address, bios_size, ROOT_SYSTEM_DESCRIPTOR_POINTER_SIGNATURE, 16)
	if rsdp !== none return rsdp

	return none as link
}

export process_madt_entries(madt: MADT*, information: SystemInformation*) {
	end = madt + madt[].header.length
	entry = (madt + capacityof(MADT)) as MADTEntryHeader*

	loop (entry < end) {
		type = entry[].type

		if type == 0 {
			# Single logical processor with a local apic
			information[].local_apic_ids[information[].local_apic_count] = entry.(u8*)[3]
			information[].local_apic_count++
		} else type == 1 {
			# Address of ioapic
			information[].ioapic_registers = (entry + 4).(u32*)[]
		} else type == 5 {
			# Address of the local apic (64-bit system version)
			information[].local_apic_registers = (entry + 4).(u64*)[]
		}

		entry += entry[].length
	}
}

export set_apic_base(base: u64) {
	value = (base & 0xfffff0000) | APIC_BASE_MSR_ENABLE
	write_msr(APIC_BASE_MSR, value)
}

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
	allocator.map_page(base as link, base as link)
	set_apic_base(base)
}

export enable_interrupts(registers: u32*) {
	# Spurious Interrupt Vector Register: "Spurious interrupt usually means an interrupt whose origin is unknown"
	value = (registers + 0xF0)[]
	(registers + 0xF0)[] = value | 0x100
}

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

export initialize() {
	rsdp = apic.find_root_system_descriptor_table()
	debug.write('rsdp: ')
	debug.write_address(rsdp as u64)
	debug.write_line()

	require(rsdp !== none, 'Failed to find rsdp')

	apic_table = find_table(rsdp, 'APIC') as MADT*
	debug.write('madt-table: ')
	debug.write_address(rsdp as u64)
	debug.write_line()

	debug.write('has-legacy-pic: ')
	debug.write_line((apic_table[].flags & 1) != 0)

	information: SystemInformation[1]
	information[].local_apic_registers = apic_table[].local_apic_address
	process_madt_entries(apic_table, information)

	local_apic_registers = information[].local_apic_registers

	debug.write('local-apic-registers: ')
	debug.write_address(information[].local_apic_registers)
	debug.write_line()

	debug.write('ioapic-registers: ')
	debug.write_address(information[].ioapic_registers)
	debug.write_line()

	debug.write('max-redirections: ')
	allocator.map_page(information[].ioapic_registers, information[].ioapic_registers)
	debug.write_line(max_redirection(information[].ioapic_registers))

	debug.write('processors: ')

	loop (i = 0, i < information[].local_apic_count, i++) {
		debug.write(information[].local_apic_ids[i])
		debug.put(` `)
	}

	debug.write_line()

	enable()
	enable_interrupts(information[].local_apic_registers)

	kernel.ioapic.initialize(information[].ioapic_registers)
	kernel.ioapic.redirect(1, 83)
	kernel.ioapic.redirect(3, 83)
	kernel.ioapic.redirect(4, 83)

	hpet_table = find_table(rsdp, 'HPET') as kernel.hpet.HPETHeader*
	debug.write('hpet-table: ')
	debug.write_address(hpet_table as u64)
	debug.write_line()

	if hpet_table !== none {
		kernel.hpet.initialize(hpet_table)
	}
}
