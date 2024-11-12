namespace kernel.multiboot

import kernel.elf
import kernel.low

constant TAG_TYPE_MEMORY_MAP = 6
constant TAG_TYPE_FRAMEBUFFER = 8
constant TAG_TYPE_SECTION_HEADER_TABLE = 9

plain RootHeader {
	size: u32
	reserved: u32
}

plain TagHeader {
	type: u32
	size: u32
}

plain MemoryMapTag {
	type: u32
	size: u32
	entry_size: u32
	entry_version: u32
}

plain MemoryMapEntry {
	base_address: u64
	length: u64
	type: u32
	reserved: u32
}

plain FramebufferTag {
	type: u32
	size: u32
	framebuffer_address: u64
	framebuffer_pitch: u32
	framebuffer_width: u32
	framebuffer_height: u32
	framebuffer_bits_per_pixel: u8
	framebuffer_type: u8
	reserved: u8
}

plain SectionHeaderTableTag {
	type: u32
	size: u32
	section_count: u32
	section_header_size: u32
	section_name_entry_index: u32
}

# Summary:
# Loads all memory regions from the specified tag into the specified region list.
# Returns the total amount of physical memory in the system based on the regions.
export process_memory_map_tag(tag: MemoryMapTag, regions: List<Segment>): u64 {
	# Add all the memory regions
	position = sizeof(MemoryMapTag)

	loop (position < tag.size) {
		entry = (tag as link + position) as MemoryMapEntry

		region = Segment.new(entry.type, entry.base_address as link, (entry.base_address + entry.length) as link)
		regions.add(region)

		# Move to the next memory region
		position += tag.entry_size
	}

	# Sort and combine the regions
	Regions.clean(regions)

	return Regions.find_physical_memory_size(regions)
}

# Summary: Processes framebuffer tags.
export process_framebuffer_tag(tag: FramebufferTag) {
	debug.write('Multiboot: Framebuffer: Address=')
	debug.write_address(tag.framebuffer_address)
	debug.write(', Width=')
	debug.write(tag.framebuffer_width)
	debug.write(', Height=')
	debug.write(tag.framebuffer_height)
	debug.write(', Bits per pixel = ')
	debug.write_line(tag.framebuffer_bits_per_pixel)
}

# Summary:
# Loads all kernel sections headers from the specified tag and adds them to the specified list.
# Returns the physical memory region that contains the kernel.
export process_section_header_table_tag(tag: SectionHeaderTableTag, section_headers: List<SectionHeader>): Segment {
	debug.write('Multiboot: Section header table = ')
	debug.write_address(tag as link)
	debug.write(', Section count = ')
	debug.write(tag.section_count)
	debug.write(', Section header size = ')
	debug.write(tag.section_header_size)
	debug.write(', "Index of the section that has names of all sections" = ')
	debug.write(tag.section_name_entry_index)
	debug.write_line()

	section_headers.reserve(tag.section_count)

	position = sizeof(SectionHeaderTableTag)
	start: u64 = 0xffffffffffffffff
	end: u64 = 0

	loop (position < tag.size) {
		# Load the current section header and move the position to the next entry 
		section_header = (tag as link + position) as SectionHeader
		position += tag.section_header_size

		section_headers.add(section_header)

		# Skip the none section
		if section_header.name == 0 continue

		start = math.min(start, section_header.virtual_address)
		end = math.max(end, section_header.virtual_address + section_header.section_file_size)

		debug.write('Multiboot: Section: ')
		debug.write('Name=') debug.write_address(section_header.name)
		debug.write(', Address=') debug.write_address(section_header.virtual_address)
		debug.write(', Size=') debug.write(section_header.section_file_size)
		debug.write_line()
	}

	debug.write('Multiboot: Kernel region ')
	debug.write_address(start)
	debug.write('-')
	debug.write_address(end)
	debug.write_line()

	return Segment.new(REGION_RESERVED, start as link, end as link)
}

# Summary:
# Finds the kernel symbol table from the specified sections and loads 
# all the symbols with their corresponding names into the specified list.
export load_symbols(sections: List<elf.SectionHeader>, symbols: List<SymbolInformation>) {
	# Find the symbol table section
	symbol_table_section = none as elf.SectionHeader

	loop (i = 0, i < sections.size, i++) {
		section = sections[i]
		if section.type != elf.ELF_SECTION_TYPE_SYMBOL_TABLE continue

		symbol_table_section = section
		stop
	}

	if symbol_table_section === none panic('Failed to find kernel symbol table')

	# Load all the symbols inside the symbol table
	symbol_count = symbol_table_section.info

	# Load the string table that contains the symbol names
	symbol_entry = mapper.to_kernel_virtual_address(symbol_table_section.virtual_address) as elf.SymbolEntry
	string_table = mapper.to_kernel_virtual_address(sections[symbol_table_section.link].virtual_address) as link

	debug.write('Multiboot: Loading symbols from ')
	debug.write_address(symbols)
	debug.write(' using string table at ')
	debug.write_address(string_table)
	debug.write_line()

	loop (i = 0, i < symbol_count, i++) {
		symbol_entry += sizeof(elf.SymbolEntry)

		# Register the symbol
		name = String.new(string_table + symbol_entry.name)
		address = symbol_entry.value as link
		symbols.add(SymbolInformation.new(name, address))

		debug.write('Multiboot: Kernel symbol: ')
		debug.put(`"`)
		debug.write(name)
		debug.put(`"`)
		debug.put(`=`)
		debug.write_address(address)
		debug.write_line()
	}
}

# Summary:
# Finds a suitable region for the physical memory manager from the specified regions
# and modifies them so that the region gets reserved. Returns the virtual address to the allocated region.
# If no suitable region can be found, this function panics.
export allocate_physical_memory_manager(regions: List<Segment>): link {
	# Compute the memory needed by the physical memory manager
	size = sizeof(PhysicalMemoryManager) + PhysicalMemoryManager.LAYER_COUNT * sizeof(Layer) + PhysicalMemoryManager.LAYER_STATE_MEMORY_SIZE

	physical_address = Regions.allocate(regions, size)
	virtual_address = mapper.map_kernel_region(physical_address, size)
	memory.zero(virtual_address, size)

	debug.write('Multiboot: Placing the physical memory manager at physical address ') debug.write_address(physical_address) debug.write_line()

	return virtual_address
}

# Summary:
# Finds a suitable region for the quickmap pages from the specified regions
# and modifies them so that the region gets reserved. Returns the physical address to the allocated region.
# If no suitable region can be found, this function panics.
export allocate_quickmap_pages(regions: List<Segment>): link {
	# Allocate quickmap pages for max 512 CPUs
	size = 512 * PAGE_SIZE

	physical_address = Regions.allocate(regions, size)
	mapper.map_kernel_region(physical_address, size)
	debug.write('Multiboot: Quickmap physical base address ') debug.write_address(physical_address) debug.write_line()

	return physical_address
}

export initialize(multiboot_information_physical_address: link, memory_information: SystemMemoryInformation) {
	regions = memory_information.regions
	reserved = memory_information.reserved
	sections = memory_information.sections
	symbols = memory_information.symbols

	# Map the multiboot information so that we can access it.
	# Note: No need to modify the paging tables, because kernel region is already mapped
	multiboot_information = mapper.to_kernel_virtual_address(multiboot_information_physical_address) as RootHeader

	debug.write('Multiboot: Header=')
	debug.write_address(multiboot_information)
	debug.write(', Size=')
	debug.write_line(multiboot_information.size)

	# Store the position inside the multiboot information
	position = sizeof(RootHeader)

	# Store the physical region where the kernel is loaded
	kernel_region = Segment.new(REGION_UNKNOWN)

	loop (position < multiboot_information.size) {
		tag = (multiboot_information as link + position) as TagHeader

		debug.write('Multiboot: Tag of type ')
		debug.write(tag.type)
		debug.write(' with size of ')
		debug.write_line(tag.size)

		if tag.type == TAG_TYPE_MEMORY_MAP {
			memory_information.physical_memory_size = process_memory_map_tag(tag as MemoryMapTag, regions)
		} else tag.type == TAG_TYPE_FRAMEBUFFER {
			process_framebuffer_tag(tag as FramebufferTag)
		} else tag.type == TAG_TYPE_SECTION_HEADER_TABLE {
			kernel_region = process_section_header_table_tag(tag as SectionHeaderTableTag, sections)
		}

		# Move over the current tag and round to the next multiple of 8
		position += tag.size
		position = memory.round_to(position, 8)
	}

	# Load the kernel symbols
	load_symbols(sections, symbols)

	require(kernel_region.type !== REGION_UNKNOWN, 'Failed to find kernel region')

	Regions.insert(regions, kernel_region) # Reserve the region where the kernel is loaded
	Regions.insert(regions, mapper.region()) # Memory used by the kernel paging tables must be reserved

	# Allocate memory for the physical memory manager and quickmap pages
	memory_information.physical_memory_manager_virtual_address = allocate_physical_memory_manager(regions)
	memory_information.quickmap_physical_base = allocate_quickmap_pages(regions)

	Regions.find_reserved_physical_regions(regions, memory_information.physical_memory_size, reserved)

	debug.write('Multiboot: Physical memory = ')
	debug.write(memory_information.physical_memory_size / MiB)
	debug.write_line(' MiB')

	loop (i = 0, i < regions.size, i++) {
		region = regions[i]

		debug.write('Multiboot: Region ')
		debug.write_address(region.start)
		debug.write('-')
		debug.write_address(region.end)
		debug.write(', Type=')
		debug.write_line(region.type)
	}

	loop (i = 0, i < reserved.size, i++) {
		region = reserved[i]

		debug.write('Multiboot: Reserved region ')
		debug.write_address(region.start)
		debug.write('-')
		debug.write_address(region.end)
		debug.write_line()
	}
}