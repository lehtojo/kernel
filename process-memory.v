namespace kernel.scheduler

plain ProcessMemory {
	# Summary: Stores the allocator used by this structure
	allocator: Allocator

	# Summary: Sorted list of virtual memory mappings (smallest virtual address to largest).
	allocations: List<MemoryMapping>

	# Summary: Available virtual address regions by address (sorted)
	available_regions_by_address: List<Segment>

	# Summary: Stores the paging table used for configuring the virtual memory of the process.
	paging_table: PagingTable

	init(allocator: Allocator) {
		this.allocator = allocator
		this.allocations = List<MemoryMapping>(allocator) using allocator
		this.available_regions_by_address = List<Segment>(allocator) using allocator
		this.paging_table = PagingTable() using allocator

		# Kernel regions must be mapped to every process, so that the kernel does not need to 
		# change the paging tables during system calls in order to access the kernel memory.
		mapper.map_kernel_entry(paging_table as u64*)

		# Map the GDT as well
		paging_table.map_gdt(allocator, Processor.current.gdtr_physical_address)

		# Add available address regions
		available_regions_by_address.add(Segment.new(0 as link, mapper.PAGE_MAP_VIRTUAL_BASE as link))

		# Reserve the GDTR page
		require(
			reserve_specific_region(GDTR_VIRTUAL_ADDRESS, PAGE_SIZE),
			'Failed to reserve GDTR page from process memory'
		)

		# Reserve the kernel mapping region
		require(
			reserve_specific_region(KERNEL_MAP_BASE, KERNEL_MAP_END - KERNEL_MAP_BASE),
			'Failed to reserve kernel mapping region from process memory'
		)
	}

	# Summary:
	# Attempts to finds a region from the specified regions, which contains the specified address.
	# If no such region is found, this function returns -1.
	private find_containing_region(regions: List<Segment>, address: link): i64 {
		debug.write('Process memory: Finding an available region that contains ') debug.write_address(address) debug.write_line()

		loop (i = 0, i < regions.size, i++) {
			region = regions[i]

			debug.write('Process memory: Processing region ')
			debug.write_address(region.start) debug.put(`-`) debug.write_address(region.end)
			debug.write_line()

			if region.contains(address) return i
		}

		debug.write_line('Process memory: No available region contained the specified size')
		return -1
	}

	private try_find_region_for_specific_virtual_address(virtual_address: u64, size: u64): i64 {
		require((size % PAGE_SIZE) == 0, 'Allocation size must be multiple of pages')
		require((virtual_address % PAGE_SIZE) == 0, 'Virtual address must be multiple of pages')

		# Find an available region, which contains the specified virtual address
		address_list_index = find_containing_region(available_regions_by_address, virtual_address as link)
		if address_list_index < 0 return -1

		address_list_region = available_regions_by_address[address_list_index]

		# Warning: Overflow seems possible here: (virtual_address + size)
		# Ensure the allocation will not go over the available region
		if virtual_address + size > address_list_region.end return -1

		return address_list_index
	}

	private allocate_specific_region(address_list_index: i64, virtual_address: u64, size: u64) {
		require((size % PAGE_SIZE) == 0, 'Allocation size must be multiple of pages')
		require((virtual_address % PAGE_SIZE) == 0, 'Virtual address must be multiple of pages')

		address_list_region = available_regions_by_address[address_list_index]

		# Todo: Look for possible overflows
		margin_left: u64 = virtual_address - address_list_region.start as u64
		margin_right: u64 = address_list_region.end - virtual_address

		# Case 1: Containing region is consumed perfectly
		if margin_left == 0 and margin_right == 0 {
			# Remove the available region entry
			available_regions_by_address.remove_at(address_list_index)
			return
		}

		# Case 2: Space is consumed from the middle of the region
		if margin_left > 0 and margin_right > 0 {
			# The region will be split into two regions:
			left_region = Segment.new(address_list_region.start, address_list_region.start + margin_left)
			right_region = Segment.new(address_list_region.end - margin_right, address_list_region.end)

			# Remove the available region entry
			available_regions_by_address.remove_at(address_list_index)

			# Insert the left and right region at the index of the removed address list entry.
			# The order will remain correct, because both the left and right region are inside the removed region.
			available_regions_by_address.insert(address_list_index, right_region)
			available_regions_by_address.insert(address_list_index, left_region)
			return
		}

		if margin_left == 0 {
			# Case 3: Space is only consumed from the start of the region

			# Consume the specified amount of bytes from the end of the region
			address_list_region.start += size
		} else {
			# Case 4: Space is only consumed from the end of the region:

			# Consume the specified amount of bytes from the end of the region
			address_list_region.end -= size
		}

		# Update the entry
		available_regions_by_address[address_list_index] = address_list_region
	}

	reserve_specific_region(virtual_address: u64, size: u64): bool {
		debug.write('Process: Reserving virtual region ')
		debug.write_address(virtual_address)
		debug.put(`-`)
		debug.write_address(virtual_address + size)
		debug.write_line()

		# Try to find an available region that can contain the specified virtual region
		address_list_index = try_find_region_for_specific_virtual_address(virtual_address, size)
		if address_list_index < 0 return false

		# Reserve the virtual region
		allocate_specific_region(address_list_index, virtual_address, size)
		return true
	}

	allocate_specific_region(virtual_address: u64, size: u64): Optional<MemoryMapping> {
		# Try to find an available region that can contain the specified virtual region
		address_list_index = try_find_region_for_specific_virtual_address(virtual_address, size)
		if address_list_index < 0 return Optionals.empty<MemoryMapping>()

		# Now we have a region that can hold the specified virtual region, but we still 
		# need the actual physical memory before allocating the region.
		physical_memory_start = PhysicalMemoryManager.instance.allocate_physical_region(size)

		# Allocate the virtual region now that we have the physical memory
		allocate_specific_region(address_list_index, virtual_address, size)

		mapping = MemoryMapping.new(virtual_address, virtual_address, physical_memory_start, size)
		allocations.add(mapping)

		return Optionals.new<MemoryMapping>(mapping)
	}

	allocate_region_anywhere(size: u64, alignment: u32): Optional<MemoryMapping> {
		require(size % PAGE_SIZE == 0, 'Allocation size was not multiple of pages')
		require(alignment % PAGE_SIZE == 0, 'Allocation alignment was not multiple of pages')

		loop (i = 0, i < available_regions_by_address.size, i++) {
			address_list_region = available_regions_by_address[i]

			# Skip regions that are not suitable for storing the specified amount of bytes
			if address_list_region.size < size + alignment continue

			# Now we have a candidate, but before taking it we must get the physical memory
			physical_memory_start = PhysicalMemoryManager.instance.allocate_physical_region(size)

			aligned_virtual_address_start = memory.round_to(address_list_region.start, alignment)
			aligned_virtual_address_end = aligned_virtual_address_start + size

			mapping = MemoryMapping.new(
				address_list_region.start as u64,
				physical_memory_start as u64,
				size
			)

			allocations.add(mapping)

			# Consume the allocated region from the available region
			if aligned_virtual_address_end == address_list_region.end {
				# The available region is consumed completely, so remove it from the list
				available_regions_by_address.remove_at(i)
			} else {
				# The available region is not consumed completely, so consume the allocated region from the start
				address_list_region.start = aligned_virtual_address_end
				available_regions_by_address[i] = address_list_region
			}

			return Optionals.new<MemoryMapping>(mapping)
		}

		return Optionals.empty<MemoryMapping>()
	}

	deallocate(virtual_address: link) {
		# Note: User can deallocate fragments
		panic('Todo: Implement deallocation')
	}

	destruct() {
		# Deallocate all the memory
		loop (i = 0, i < allocations.size, i++) {
			mapping = allocations[i]

			debug.write('Process: Deallocating physical memory region ')
			debug.write_address(mapping.physical_address_start)
			debug.put(`-`)
			debug.write_address(mapping.physical_address_start + mapping.size)
			debug.write_line()

			# Deallocate the physical allocation
			PhysicalMemoryManager.instance.deallocate(mapping.physical_address_start as link)
		}

		debug.write_line('Process: Deallocated all process memory')

		# Destruct the lists
		allocations.destruct(allocator)
		available_regions_by_address.destruct(allocator)
		paging_table.destruct(allocator)

		allocator.deallocate(this as link)
	}
}