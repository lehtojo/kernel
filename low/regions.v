namespace kernel.low.Regions

# Summary:
# Finds a suitable region for the specified amount of memory from the specified regions
# and modifies them so that the region gets reserved. Returns the virtual address to the allocated region.
# If no suitable region can be found, this function panics.
export allocate(regions: List<Segment>, size: u64): link {
	size = memory.round_to_page(size)

	loop (i = 0, i < regions.size, i++) {
		# Find the first available region that can store the specified amount of bytes
		region = regions[i]
		if region.type != REGION_AVAILABLE or region.size < size continue

		reservation = Segment.new(REGION_RESERVED, region.start, region.start + size)
		insert(regions, reservation)

		return region.start
	}

	panic('Failed to find a suitable physical memory region')
}

# Summary:
# Sort the specified regions so that lower addresses are first.
# Combine intersection regions as well.
export clean(regions: List<Segment>) {
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

# Summary: Returns the size of the physical memory based on the specified memory regions. Panics upon failure.
export find_physical_memory_size(regions: List<Segment>): u64 {
	loop (i = regions.size - 1, i >= 0, i--) {
		region = regions[i]
		if region.type == REGION_AVAILABLE return region.end as u64
	}

	panic('Failed to find the physical memory size')
}

export find_reserved_physical_regions(regions: List<Segment>, physical_memory_size: u64, reserved: List<Segment>) {
	debug.write_line('Regions: Finding reserved regions...')
	start = none as link

	loop (i = 0, i < regions.size, i++) {
		region = regions[i]
		if region.type != REGION_AVAILABLE continue

		# Stop after passing the physical memory regions.
		# It seems that some regions are virtual (memory-mapped devices?)
		if region.start >= physical_memory_size stop

		end = region.start
		reserved_region = Segment.new(REGION_RESERVED, start, end)

		debug.write('Regions: Found reserved region: ')
		reserved_region.print()
		debug.write_line()

		# Add the reserved region if it is not empty
		if reserved_region.size > 0 reserved.add(reserved_region)

		# Start the next reserved region after the available region
		start = region.end
	}

	debug.write_line('Regions: All reserved regions added')
}

# Summary: Adds the specified region to the specified regions by splitting the intersecting regions
export insert(regions: List<Segment>, region: Segment) {
	if region.size <= 0 return

	loop (i = 0, i < regions.size, i++) {
		current = regions[i]

		# Skip the current region if the specified region is not inside it
		if region.start < current.start or region.end > current.end continue

		# General idea:
		# current.start    region.start region.end    current.end 
		#        v               v            v              v     
		#    ... [    current    |   region   |   fragment   ] ... 
		fragment = Segment.new(current.type, region.end, current.end)
		current.end = region.start

		# Add the fragment if it is not empty
		if fragment.size > 0 regions.insert(i + 1, fragment)

		# Add the region, because it can not be empty
		regions.insert(i + 1, region)

		# Remove the current region if it has become empty, update it otherwise
		if current.size > 0 {
			regions[i] = current
		} else {
			regions.remove_at(i)
		}

		return
	}
}