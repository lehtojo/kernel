namespace kernel.scheduler

plain ProcessMemory {
	# Summary: Stores the allocator used by this structure
	allocator: Allocator

	# Summary: Sorted list of virtual memory mappings (smallest virtual address to largest).
	allocations: List<Segment>

	# Summary: Available virtual address regions by address (sorted)
	available_regions_by_address: List<Segment>

	# Summary: Stores the paging table used for configuring the virtual memory of the process.
	paging_table: PagingTable

	# Todo: Consider moving the members below into an object (name might be limits?)

	# Summary: Minimum address that automatic memory mapping may return
	min_memory_map_address: u64

	# Summary: Stores the current program break address that the process can adjust
	break: u64

	# Summary: Stores the maximum allowed value for the program break
	max_break: u64

	init(allocator: Allocator) {
		this.allocator = allocator
		this.allocations = List<MemoryMapping>(allocator) using allocator
		this.available_regions_by_address = List<Segment>(allocator) using allocator
		this.paging_table = PagingTable() using allocator
		this.min_memory_map_address = 0x1000000 # Todo: Use a constant
		this.break = 0
		this.max_break = mapper.PAGE_MAP_VIRTUAL_BASE

		# Kernel regions must be mapped to every process, so that the kernel does not need to 
		# change the paging tables during system calls in order to access the kernel memory.
		mapper.map_kernel_entry(paging_table as u64*)

		# Map the GDT as well
		paging_table.map_gdt(allocator, Processor.current.gdtr_physical_address)

		# Add available address regions
		available_regions_by_address.add(Segment.new(0 as link, min_memory_map_address as link))
		available_regions_by_address.add(Segment.new(min_memory_map_address as link, mapper.PAGE_MAP_VIRTUAL_BASE as link))

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

	# Summary: Adds the specified allocation into the sorted allocation list
	add_allocation(allocation: Segment): _ {
		memory.sorted.insert<Segment>(allocations, allocation, (a: Segment, b: Segment) -> (a.start - b.start) as i64)
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

	allocate_specific_region(virtual_address: u64, size: u64): bool {
		# Try to find an available region that can contain the specified virtual region
		address_list_index = try_find_region_for_specific_virtual_address(virtual_address, size)
		if address_list_index < 0 return false

		# Allocate the virtual region now that we have the physical memory
		allocate_specific_region(address_list_index, virtual_address, size)

		add_allocation(Segment.new(virtual_address as link, virtual_address as link + size))
		return true
	}

	# Summary:
	# Attempts to allocate a new memory region of the specified size from anywhere in the virtual address space.
	# The returned region will respect the specified alignment.
	allocate_region_anywhere(size: u64, alignment: u32): Optional<u64> {
		require(size % PAGE_SIZE == 0, 'Allocation size was not multiple of pages')
		require(alignment % PAGE_SIZE == 0, 'Allocation alignment was not multiple of pages')

		loop (i = 0, i < available_regions_by_address.size, i++) {
			address_list_region = available_regions_by_address[i]

			# Skip regions that are below the minimum address
			if address_list_region.start < min_memory_map_address continue

			# Skip regions that are not suitable for storing the specified amount of bytes
			if address_list_region.size < size + alignment continue

			unaligned_virtual_address_start = address_list_region.start
			aligned_virtual_address_start = memory.round_to(unaligned_virtual_address_start, alignment)
			aligned_virtual_address_end = aligned_virtual_address_start + size

			# Insert the allocation being made into the sorted allocation list
			add_allocation(Segment.new(unaligned_virtual_address_start, aligned_virtual_address_end))

			# Consume the allocated region from the available region
			if aligned_virtual_address_end == address_list_region.end {
				# The available region is consumed completely, so remove it from the list
				available_regions_by_address.remove_at(i)
			} else {
				# The available region is not consumed completely, so consume the allocated region from the start
				address_list_region.start = aligned_virtual_address_end
				available_regions_by_address[i] = address_list_region
			}

			return aligned_virtual_address_start
		}

		return Optionals.empty<u64>()
	}

	# Summary:
	# Processes page fault at the specified address.
	# If the specified address is in an allocated page that is accessible for 
	# the process, the page is mapped and this function returns true.
	# Otherwise if the specified address is not accessible, 
	# this function returns false.
	process_page_fault(virtual_address: u64, write: bool): bool {
		# Attempt to find the allocation that contains the specified address
		i = -1

		loop (j = 0, j < allocations.size, j++) {
			allocation = allocations[j]

			if virtual_address >= allocation.start and virtual_address < allocation.end {
				i = j
				stop
			}
		}

		# Return false, if no allocated region contained the specified address
		if i < 0 return false

		# Todo: Verify access rights here?

		# Align the virtual address to pages, so we know which page to map
		virtual_page = virtual_address & (-PAGE_SIZE)

		# Attempt to allocate a physical page for the virtual page
		physical_page = PhysicalMemoryManager.instance.allocate_physical_region(PAGE_SIZE)
		if physical_page === none return false

		# Map the new physical page to the accessed virtual page and continue as normal
		paging_table.map_page(allocator, virtual_page as link, physical_page)
		return true
	}

	# Summary: Deallocates the specified region allowing fragmentation
	deallocate(virtual_region: Segment): i64 {
		# Validate the specified region before doing anything with it
		require(virtual_region.start % PAGE_SIZE == 0 and virtual_region.size % PAGE_SIZE == 0, 'Virtual region was not aligned')

		# Empty regions can not be deallocated
		if virtual_region.size == 0 return EINVAL

		# Find the index of the allocation that contains the virtual region that should be deallocated 
		containing_virtual_region_index = find_containing_region(allocations, virtual_region.start)
		if containing_virtual_region_index < 0 return EINVAL # Todo: Error might not be correct
		
		# Load the containing virtual region that we found
		containing_virtual_region = allocations[containing_virtual_region_index]

		# Verify the specified region actually fits inside the "containing region"
		if not containing_virtual_region.contains(virtual_region) return EINVAL # Todo: Error might not be correct

		# Deallocate all pages in the specified virtual region
		loop (virtual_page = virtual_region.start, virtual_page < virtual_region.end, virtual_page += PAGE_SIZE) {
			if paging_table.to_physical_address(virtual_page as link) has not physical_page continue
			PhysicalMemoryManager.instance.deallocate_all(physical_page)
		}

		# Compute the regions that will remain after the deallocation
		remaining_left_region = Segment.new(containing_virtual_region.start, virtual_region.start)
		remaining_right_region = Segment.new(virtual_region.end, containing_virtual_region.end)

		# Remove the allocation from the list
		allocations.remove_at(containing_virtual_region_index)

		# Insert back the remaining regions in order if they are not empty
		if remaining_right_region.size > 0 allocations.insert(containing_virtual_region_index, remaining_right_region)
		if remaining_left_region.size > 0 allocations.insert(containing_virtual_region_index, remaining_left_region)

		return 0
	}

	# Summary: Deallocates all the memory this process has allocated
	private deallocate() {
		debug.write_line('Process: Deallocating all process memory')

		loop (i = 0, i < allocations.size, i++) {
			allocation = allocations[i]

			debug.write('Process: Deallocating virtual region ')
			debug.write_address(allocation.start)
			debug.put(`-`)
			debug.write_address(allocation.end)
			debug.write_line()

			page = allocation.start

			loop (page < allocation.end) {
				if paging_table.to_physical_address(page as link) has not physical_address {
					page += PAGE_SIZE
					continue
				} 

				debug.write('Process: Deallocating physical page ')
				debug.write_address(physical_address)
				debug.write_line()
				page += PhysicalMemoryManager.instance.deallocate_all(physical_address)
			}
		}

		debug.write_line('Process: Deallocated all process memory')
	}

	destruct() {
		deallocate()

		# Destruct the lists
		allocations.destruct(allocator)
		available_regions_by_address.destruct(allocator)
		paging_table.destruct(allocator)

		allocator.deallocate(this as link)
	}
}