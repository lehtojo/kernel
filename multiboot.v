namespace kernel.multiboot

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

export process_memory_regions(regions: List<Segment>) {
	# Sort the regions so that lower addresses are first
	sort<Segment>(regions, (a: Segment, b: Segment) -> (a.start - b.start) as i64)

	i = 0

	loop (i < regions.size - 1) {
		current = regions[i]
		next = regions[i + 1]

		# If the regions intersect, combine them
		if current.end > next.start and current.start < next.end {
			current.start = math.min(current.start, next.start)
			current.end = math.max(current.end, next.end)
			regions.remove_at(i + 1)
			continue
		}

		i++
	}
}

export process_memory_map_tag(tag: MemoryMapTag, regions: List<Segment>) {
	debug.write_line('memory-map-regions: ')

	position = capacityof(MemoryMapTag)

	loop (position < tag.size) {
		entry = (tag as link + position) as MemoryMapEntry

		region = pack {
			start: entry.base_address,
			end: entry.base_address + entry.length,
			type: entry.type
		} as Segment

		regions.add(region)

		position += tag.entry_size
	}

	process_memory_regions(regions)

	loop (i = 0, i < regions.size, i++) {
		region = regions[i]

		debug.write('region: ')
		debug.write_address(region.start)
		debug.write('-')
		debug.write_address(region.end)
		debug.write(', type: ')
		debug.write(region.type)
		debug.write_line()
	}
}

export process_framebuffer_tag(tag: FramebufferTag) {
	debug.write('framebuffer-address: ')
	debug.write_address(tag.framebuffer_address)
	debug.write_line()
	debug.write('framebuffer-width: ')
	debug.write_line(tag.framebuffer_width)
	debug.write('framebuffer-height: ')
	debug.write_line(tag.framebuffer_height)
	debug.write('framebuffer-bits-per-pixel: ')
	debug.write_line(tag.framebuffer_bits_per_pixel)
}

export process_section_header_table_tag(tag: SectionHeaderTableTag) {
	debug.write('kernel-section-header-table: ')
	debug.write_address(tag as link)
	debug.write_line()
	debug.write('kernel-section-count=')
	debug.write(tag.section_count)
	debug.write(', kernel-section-header-size=')
	debug.write(tag.section_header_size)
	debug.write(', kernel-section-name-entry-index=')
	debug.write(tag.section_name_entry_index)
	debug.write_line()

	position = capacityof(SectionHeaderTableTag)
	start = 0xffffffffffffffff
	end = 0

	loop (position < tag.size) {
		section_header = (tag as link + position) as kernel.elf.SectionHeader
		position += tag.section_header_size

		# Skip the none section
		if section_header.name == 0 continue

		start = math.min(start, section_header.virtual_address)
		end = math.max(end, section_header.virtual_address + section_header.section_file_size)

		debug.write('kernel-section: ')
		debug.write('name=') debug.write_address(section_header.name)
		debug.write(', address=') debug.write_address(section_header.virtual_address)
		debug.write(', size=') debug.write(section_header.section_file_size)
		debug.write_line()
	}

	debug.write('kernel-region: ')
	debug.write_address(start)
	debug.write('-')
	debug.write_address(end)
	debug.write_line()
}

export initialize(information: link, regions: List<Segment>) {
	debug.write('multiboot-header: ')
	debug.write_address(information)
	debug.write_line()

	header = information as RootHeader
	debug.write('multiboot-header-size: ')
	debug.write_line(header.size)

	position = capacityof(RootHeader)

	loop (position < header.size) {
		tag = (information + position) as TagHeader

		debug.write('multiboot-tag-type: ')
		debug.write_line(tag.type)

		debug.write('multiboot-tag-size: ')
		debug.write_line(tag.size)

		if tag.type == TAG_TYPE_MEMORY_MAP {
			process_memory_map_tag(tag as MemoryMapTag, regions)
		} else tag.type == TAG_TYPE_FRAMEBUFFER {
			process_framebuffer_tag(tag as FramebufferTag)
		} else tag.type == TAG_TYPE_SECTION_HEADER_TABLE {
			process_section_header_table_tag(tag as SectionHeaderTableTag)
		}

		position += tag.size

		# Round to the next multiple of 8
		position = (position + 7) & (-8)
	}
}