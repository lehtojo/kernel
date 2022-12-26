namespace kernel.scheduler

pack MemoryMapping {
	unaligned_virtual_address_start: u64
	virtual_address_start: u64
	physical_address_start: u64
	size: u64

	shared new(virtual_address_start: u64, physical_address_start: u64, size: u64): MemoryMapping {
		return pack {
			unaligned_virtual_address_start: virtual_address_start,
			virtual_address_start: virtual_address_start,
			physical_address_start: physical_address_start,
			size: size
		} as MemoryMapping
	}
}

ProcessMemoryManager {
	# Summary: Sorted list of virtual memory mappings (smallest to largest).
	mappings: List<MemoryMapping>

	# Summary: Sorted list of available virtual memory regions (smallest to largest).
	available_regions: List<Segment>

	allocate_region_anywhere(size: u64, alignment: u32): Optional<MemoryMapping> {
		require((size % PAGE_SIZE) == 0, 'Allocation size must be multiple of pages')
		require((alignment % PAGE_SIZE) == 0, 'Allocation alignment must be multiple of pages')

		# Search the first possible available region that can store the specified amount of bytes
		candidate = -1
		low = 0
		high = available_regions.size

		loop (high - low > 0) {
			middle = (low + high) / 2
			region = available_regions[middle]

			# Since we must support alignment, sometimes we need padding in order to make region aligned
			padding: u64 = memory.align(region.start, alignment) - region.start

			if region.size >= (size + padding) {
				# Because the region can store the specified amount of bytes, set it as candidate
				# candidate = middle

				# Regions within range low..middle can store less or equal amount of bytes as the middle region,
				# so search for candidates whose size is closer to the specified amount of bytes.
				high = middle
			} else {
				# Regions within range middle..high can store more or equal amount of bytes as the middle region,
				# so search for candidates from that range.
				low = middle
			}
		}

		# Return an error, if no suitable candidate could be found
		if candidate < 0 return Optionals.empty<MemoryMapping>()

		# Since we now have a suitable candidate, before doing anything we must get the actual physical memory
		physical_address_start = KernelHeap.allocate(size)
		if physical_address_start === none return Optionals.empty<MemoryMapping>()

		# Load the available region from which we allocate
		region = available_regions[candidate]

		# Remove the region from the list, because its size will shrink and the list must remain sorted
		available_regions.remove_at(candidate)

		# Compute the virtual start and end addresses of result region
		virtual_address_start = memory.align(region.start, alignment)
		virtual_address_end = virtual_address_start + size

		mapping = MemoryMapping.new(region.start as u64, virtual_address_start as u64, size)

		# Since the region (region.start)..(virtual_address_end) is consumed from the region, update its start address
		region.start = virtual_address_end

		# If the region is now empty, do not add it back
		if region.size == 0 return Optionals.new<MemoryMapping>(mapping)

		# TODO: Add the shrunken region back and keep the list sorted
		return Optionals.new<MemoryMapping>(mapping)
	}
}