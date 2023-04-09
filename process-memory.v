namespace kernel.scheduler

constant DEFAULT_MIN_MEMORY_MAP_ADDRESS = 0x1000000

constant PROCESS_ALLOCATION_PROGRAM_TEXT = 1
constant PROCESS_ALLOCATION_PROGRAM_DATA = 2
constant PROCESS_ALLOCATION_RUNTIME_DATA = 4

pack ProcessMemoryRegionOptions {
	# Summary: Stores an inode if this region is mapped to an inode
	inode: Optional<Inode>

	# Summary: Stores an offset
	offset: u64

	shared new(): ProcessMemoryRegionOptions {
		return pack {
			inode: Optionals.empty<Inode>(),
			offset: 0 as u64
		} as ProcessMemoryRegionOptions
	}
}

pack ProcessMemoryRegion {
	# Summary: Stores the virtual address region of this memory region
	region: Segment

	# Summary: Stores an inode if this region is mapped to an inode
	inode: Optional<Inode>

	# Summary: Stores an offset
	offset: u64

	# Summary: Returns a process memory region mapped to the specified inode
	shared new(region: Segment, inode: Inode, offset: u64): ProcessMemoryRegion {
		return pack {
			region: region,
			inode: Optionals.new<Inode>(inode),
			offset: offset
		} as ProcessMemoryRegion
	}

	# Summary: Returns a process memory region mapped to the specified inode
	shared new(region: Segment, inode: Optional<Inode>, offset: u64): ProcessMemoryRegion {
		return pack {
			region: region,
			inode: inode,
			offset: offset
		} as ProcessMemoryRegion
	}

	# Summary: Returns a normal process memory region
	shared new(region: Segment): ProcessMemoryRegion {
		return pack {
			region: region,
			inode: Optionals.empty<Inode>(),
			offset: 0 as u64
		} as ProcessMemoryRegion
	}

	# Summary: Returns a process memory region based on the specified options
	shared new(region: Segment, options: ProcessMemoryRegionOptions): ProcessMemoryRegion {
		return pack {
			region: region,
			inode: options.inode,
			offset: options.offset
		} as ProcessMemoryRegion
	}

	# Summary: Returns a slice of this region
	slice(slice: Segment): ProcessMemoryRegion {
		require(slice.start >= region.start, 'Slice start must be greater than or equal to region start')
		require(slice.end <= region.end, 'Slice end must be less than or equal to region end')
		require(slice.start <= slice.end, 'Slice start must be less than slice end')

		return ProcessMemoryRegion.new(slice, inode, offset)
	}

	# Summary: Returns a slice of this region
	slice(start, end): ProcessMemoryRegion {
		return slice(Segment.new(start, end))
	}

	# Summary: Returns whether this region can be merged with the specified region
	can_merge(other: ProcessMemoryRegion): bool {
		# Regions can not be merged if they have different inodes
		if not (inode == other.inode) return false

		# If there is inode, merge only if the inode regions are adjecent
		if not inode.empty and offset + region.size != other.offset return false

		# Regions can be merged if they are adjacent
		return region.end == other.region.start
	}

	# Summary: Merges this region with the specified region
	merge(other: ProcessMemoryRegion): this {
		require(can_merge(other), 'Can not merge regions')

		region.end = other.region.end
	}
}

plain ProcessMemory {
	# Summary: Stores the allocator used by this structure
	allocator: Allocator

	# Summary: Sorted list of virtual memory mappings (smallest virtual address to largest).
	allocations: List<ProcessMemoryRegion>

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
		this.allocations = List<ProcessMemoryRegion>(allocator) using allocator
		this.available_regions_by_address = List<Segment>(allocator) using allocator
		this.paging_table = PagingTable() using allocator
		this.min_memory_map_address = DEFAULT_MIN_MEMORY_MAP_ADDRESS
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
		remove_intersecting_available_regions(ProcessMemoryRegion.new(Segment.new(GDTR_VIRTUAL_ADDRESS, GDTR_VIRTUAL_ADDRESS + PAGE_SIZE)))

		# Reserve the kernel mapping region
		remove_intersecting_available_regions(ProcessMemoryRegion.new(Segment.new(KERNEL_MAP_BASE, KERNEL_MAP_END)))
	}

	# Summary: Removes intersecting regions from the allocation list
	private remove_intersecting_allocations(allocation: ProcessMemoryRegion): _ {
		region = allocation.region

		# Find the last intersecting region
		# Todo: Later this could be optimized with binary search?
		intersecting_index = allocations.find_last_index<Segment>(
			region, 
			(i: ProcessMemoryRegion, region: Segment) -> i.region.intersects(region)
		)

		# Remove all intersecting regions
		loop (i = intersecting_index, i >= 0, i--) {
			intersecting = allocations[i]

			# Check if the region is intersecting
			if not intersecting.region.intersects(region) stop

			# Subtract the allocation region from the current region
			remaining = intersecting.region.subtract(region)

			# Remove the current region from the allocations
			allocations.remove_at(i)

			# Add the remaining right region
			if remaining.right.size > 0 {
				allocations.insert(i, intersecting.slice(remaining.right))
			}

			# Add the remaining left region
			if remaining.left.size > 0 {
				allocations.insert(i, intersecting.slice(remaining.left))
			}
		}
	}

	# Summary: Removes intersecting regions from the available regions
	private remove_intersecting_available_regions(allocation: ProcessMemoryRegion): _ {
		region = allocation.region

		# Find the last intersecting region
		# Todo: Later this could be optimized with binary search?
		intersecting_index = available_regions_by_address.find_last_index<Segment>(
			region, 
			(i: Segment, region: Segment) -> i.intersects(region)
		)

		# Remove all intersecting regions
		loop (i = intersecting_index, i >= 0, i--) {
			intersecting = available_regions_by_address[i]

			# Check if the region is intersecting
			if not intersecting.intersects(region) stop

			# Subtract the allocation region from the current region
			remaining = intersecting.subtract(region)

			# Remove the current region from the available regions
			available_regions_by_address.remove_at(i)

			# Add the remaining right region
			if remaining.right.size > 0 {
				available_regions_by_address.insert(i, remaining.right)
			}

			# Add the remaining left region
			if remaining.left.size > 0 {
				available_regions_by_address.insert(i, remaining.left)
			}
		}
	}

	# Summary: Merges regions in the specified list
	private merge_regions(regions: List<ProcessMemoryRegion>): _ {
		# Iterate all regions and merge them if possible
		loop (i = regions.size - 2, i >= 0, i--) {
			region = regions[i]
			other = regions[i + 1]

			# Check if the regions can be merged
			if not region.can_merge(other) continue

			# Merge the regions
			region.merge(other)

			# Remove the other region
			regions.remove_at(i + 1)
		
			# Place the merged region at the same index
			regions[i] = region
		}
	}

	# Summary: Writes the current allocations to debug console
	print_allocations(): _ {
		debug.write_line('Process memory allocations: ')

		loop (i = 0, i < allocations.size, i++) {
			allocation = allocations[i]

			# Output the region
			debug.write('  ')
			debug.write_address(allocation.region.start)
			debug.put(`-`)
			debug.write_address(allocation.region.end)

			# Output the inode
			if not allocation.inode.empty {
				debug.write(' inode=')
				allocation.inode.get_value().identifier.print()
				debug.write(', offset=')
				debug.write_address(allocation.offset)
			}

			debug.write_line()
		}
	}

	# Summary: Adds the specified allocation into the sorted allocation list
	add_allocation(type: u8, allocation: ProcessMemoryRegion): _ {
		# Update the type of the region
		allocation.region.type = type

		# Remove intersecting available regions
		remove_intersecting_available_regions(allocation)

		# Remove intersecting regions from allocations
		remove_intersecting_allocations(allocation)

		# Now the allocation can be inserted safely, because all intersections have been removed
		memory.sorted.insert<ProcessMemoryRegion>(
			allocations,
			allocation,
			(a: ProcessMemoryRegion, b: ProcessMemoryRegion) -> (a.region.start - b.region.start) as i64
		)

		# Merge the allocated region with the existing allocations
		merge_regions(allocations)

		# Output debug information
		print_allocations()
	}

	# Summary: Allocates or updates the specified virtual region
	allocate_specific_region(allocation: ProcessMemoryRegion): bool {
		# Output debug information
		debug.write('Process memory: Allocating a specific region ')
		allocation.region.print()
		debug.write_line()

		add_allocation(PROCESS_ALLOCATION_RUNTIME_DATA, allocation)
	}

	# Summary:
	# Attempts to allocate a new memory region of the specified size from anywhere in the virtual address space.
	# The returned region will respect the specified alignment.
	allocate_region_anywhere(options: ProcessMemoryRegionOptions, size: u64, alignment: u32): Optional<u64> {
		# Output debug information
		debug.write('Process memory: Allocating a region from anywhere size=')
		debug.write(size)
		debug.write(' alignment=')
		debug.write(alignment)
		debug.write_line()

		require(size % PAGE_SIZE == 0, 'Allocation size was not multiple of pages')
		require(alignment % PAGE_SIZE == 0, 'Allocation alignment was not multiple of pages')

		loop (i = 0, i < available_regions_by_address.size, i++) {
			address_list_region = available_regions_by_address[i]

			# Skip regions that are below the minimum address
			if address_list_region.start < min_memory_map_address continue

			# Skip regions that are not suitable for storing the specified amount of bytes
			if address_list_region.size < size + alignment continue

			# Output debug information
			debug.write('Process memory: Found available region ')
			address_list_region.print()
			debug.write_line()

			unaligned_virtual_address_start = address_list_region.start
			aligned_virtual_address_start = memory.round_to(unaligned_virtual_address_start, alignment)
			aligned_virtual_address_end = aligned_virtual_address_start + size

			# Insert the allocation being made into the sorted allocation list
			allocation = ProcessMemoryRegion.new(
				Segment.new(unaligned_virtual_address_start, aligned_virtual_address_end),
				options
			)

			# Add the allocation and return it
			add_allocation(PROCESS_ALLOCATION_RUNTIME_DATA, allocation)
			return Optionals.new<u64>(aligned_virtual_address_start as u64)
		}

		return Optionals.empty<u64>()
	}

	# Summary: Initializes the specified physical page based on the allocation
	private initialize_physical_page(allocation: ProcessMemoryRegion, virtual_page: link, physical_page: link): _ {
		# Map the physical page, so that we can write to it
		mapped_physical_page = mapper.map_kernel_page(physical_page)

		# Zero the allocated physical page
		memory.zero(mapped_physical_page, PAGE_SIZE)

		# Compute the offset inside the allocation
		internal_offset: u64 = virtual_page - allocation.region.start

		if not allocation.inode.empty {
			debug.write_line('Process memory: Initializing physical page from inode')
			inode = allocation.inode.get_value()

			# Compute the offset where we should read
			offset = allocation.offset + internal_offset

			# Todo: Remove
			debug.write('allocation.start=')
			debug.write_address(allocation.region.start)
			debug.write(', virtual_page=')
			debug.write_address(virtual_page)
			debug.write(', allocation.offset=')
			debug.write(allocation.offset)
			debug.write(', internal_offset=')
			debug.write(internal_offset)
			debug.write(', inode.size=')
			debug.write(inode.size())
			debug.write_line()

			# Compute how many bytes should be read
			read_size = math.min(inode.size() - offset, PAGE_SIZE)

			# Initialize the contents of the page based on the inode
			inode.read_bytes(mapped_physical_page, offset, read_size)
			return
		}
	}

	# Summary:
	# Processes page fault at the specified address.
	# If the specified address is in an allocated page that is accessible for 
	# the process, the page is mapped and this function returns true.
	# Otherwise if the specified address is not accessible, 
	# this function returns false.
	process_page_fault(virtual_address: u64, write: bool): bool {
		# Attempt to find the allocation that contains the specified address
		allocation = none as ProcessMemoryRegion
		i = -1

		loop (j = 0, j < allocations.size, j++) {
			allocation = allocations[j]

			if virtual_address >= allocation.region.start and virtual_address < allocation.region.end {
				i = j
				stop
			}
		}

		# Return false, if no allocated region contained the specified address
		if i < 0 return false

		# Todo: Verify access rights here?

		# Align the virtual address to pages, so we know which page to map
		virtual_page: link = virtual_address & (-PAGE_SIZE)

		# Attempt to allocate a physical page for the virtual page
		physical_page = PhysicalMemoryManager.instance.allocate_physical_region(PAGE_SIZE)
		if physical_page === none return false

		# Initialize the contents of the accessed page
		initialize_physical_page(allocation, virtual_page, physical_page)

		# Map the new physical page to the accessed virtual page and continue as normal
		paging_table.map_page(allocator, virtual_page, physical_page)
		return true
	}

	# Summary: Deallocates all programs allocations and removes them from the allocation list
	deallocate_program_allocations() {
		loop (i = allocations.size - 1, i >= 0, i--) {
			# Skip runtime allocations
			region = allocations[i].region
			if region.type != PROCESS_ALLOCATION_PROGRAM_TEXT and region.type != PROCESS_ALLOCATION_PROGRAM_DATA continue

			# Deallocate the program allocation and remove it from the allocations
			allocations.remove_at(i)
			deallocate(region)
		}
	}
 
	# Summary: Deallocates the specified region allowing fragmentation
	deallocate(virtual_region: Segment): i64 {
		# Validate the specified region before doing anything with it
		require(virtual_region.start % PAGE_SIZE == 0 and virtual_region.size % PAGE_SIZE == 0, 'Virtual region was not aligned')
		print_allocations()

		# Empty regions can not be deallocated
		if virtual_region.size == 0 return EINVAL

		# Find the index of the allocation that contains the virtual region that should be deallocated 
		containing_virtual_region_index = allocations.find_index<link>(
			virtual_region.start,
			(i: ProcessMemoryRegion, start: link) -> i.region.contains(start)
		)
		if containing_virtual_region_index < 0 return EINVAL # Todo: Error might not be correct
		
		# Load the containing virtual region that we found
		containing_virtual_allocation = allocations[containing_virtual_region_index]
		containing_virtual_region = containing_virtual_allocation.region

		# Verify the specified region actually fits inside the "containing region"
		if not containing_virtual_region.contains(virtual_region) return EINVAL # Todo: Error might not be correct

		# Deallocate all pages in the specified virtual region
		loop (virtual_page = virtual_region.start, virtual_page < virtual_region.end, virtual_page += PAGE_SIZE) {
			if paging_table.to_physical_address(virtual_page as link) has not physical_page continue
			PhysicalMemoryManager.instance.deallocate_all(physical_page)
		}

		# Compute the regions that will remain after the deallocation
		remaining_left_region = containing_virtual_allocation.slice(containing_virtual_region.start, virtual_region.start)
		remaining_right_region = containing_virtual_allocation.slice(virtual_region.end, containing_virtual_region.end)

		# Remove the allocation from the list
		allocations.remove_at(containing_virtual_region_index)

		# Insert back the remaining regions in order if they are not empty
		if remaining_right_region.region.size > 0 allocations.insert(containing_virtual_region_index, remaining_right_region)
		if remaining_left_region.region.size > 0 allocations.insert(containing_virtual_region_index, remaining_left_region)

		# Output debug information about the remaining allocations
		print_allocations()
		return 0
	}

	# Summary: Deallocates all the memory this process has allocated
	private deallocate() {
		debug.write_line('Process: Deallocating all process memory')

		loop (i = 0, i < allocations.size, i++) {
			region = allocations[i].region

			debug.write('Process: Deallocating virtual region ')
			debug.write_address(region.start)
			debug.put(`-`)
			debug.write_address(region.end)
			debug.write_line()

			page = region.start

			loop (page < region.end) {
				# Get the physical page backing the current virtual page
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