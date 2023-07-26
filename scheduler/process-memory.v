namespace kernel.scheduler

constant DEFAULT_MIN_MEMORY_MAP_ADDRESS = 0x1000000

constant PROCESS_ALLOCATION_PROGRAM_TEXT = 1
constant PROCESS_ALLOCATION_PROGRAM_DATA = 2
constant PROCESS_ALLOCATION_RUNTIME_DATA = 4

# Summary: Stores all processes that share the memory region
plain MemoryRegionOwners {
	# Summary: Stores the process ids that own this memory region
	pids: List<u32>

	init(allocator: Allocator) {
		this.pids = List<u32>(allocator) using allocator
	}

	add(pid: u32): _ {
		pids.add(pid)
	}
}

pack ProcessMemoryRegionOptions {
	# Summary: Stores an inode if this region is mapped to an inode
	inode: Optional<Inode>

	# Summary: Stores a device if this region is mapped to a device
	device: Optional<Device>

	# Summary: Stores an offset
	offset: u64

	shared new(): ProcessMemoryRegionOptions {
		return pack {
			inode: Optionals.empty<Inode>(),
			device: Optionals.empty<Device>(),
			offset: 0 as u64
		} as ProcessMemoryRegionOptions
	}
}

pack ProcessMemoryRegion {
	# Summary: Stores the virtual address region of this memory region
	region: Segment

	# Summary: Stores an inode if this region is mapped to an inode
	inode: Optional<Inode>

	# Summary: Stores an device if this region is mapped to an inode
	device: Optional<Device>

	# Summary: Stores an offset
	offset: u64

	# Summary: Stores the owners of this region. If set to none, this process owns ths region.
	owners: MemoryRegionOwners

	# Summary: Returns a process memory region mapped to the specified inode
	shared new(region: Segment, inode: Optional<Inode>, device: Optional<Device>, offset: u64): ProcessMemoryRegion {
		return pack {
			region: region,
			inode: inode,
			device: device,
			offset: offset,
			owners: none as MemoryRegionOwners
		} as ProcessMemoryRegion
	}

	# Summary: Returns a normal process memory region
	shared new(region: Segment): ProcessMemoryRegion {
		return pack {
			region: region,
			inode: Optionals.empty<Inode>(),
			device: Optionals.empty<Device>(),
			offset: 0 as u64,
			owners: none as MemoryRegionOwners
		} as ProcessMemoryRegion
	}

	# Summary: Returns a process memory region based on the specified options
	shared new(region: Segment, options: ProcessMemoryRegionOptions): ProcessMemoryRegion {
		return pack {
			region: region,
			inode: options.inode,
			device: options.device,
			offset: options.offset,
			owners: none as MemoryRegionOwners
		} as ProcessMemoryRegion
	}

	# Summary: Returns a slice of this region
	slice(slice: Segment): ProcessMemoryRegion {
		require(slice.start >= region.start, 'Slice start must be greater than or equal to region start')
		require(slice.end <= region.end, 'Slice end must be less than or equal to region end')
		require(slice.start <= slice.end, 'Slice start must be less than slice end')

		internal_offset = (slice.start - region.start) as u64
		return ProcessMemoryRegion.new(slice, inode, device, offset + internal_offset)
	}

	# Summary: Returns a slice of this region
	slice(start, end): ProcessMemoryRegion {
		return slice(Segment.new(start, end))
	}

	# Summary: Returns whether this region can be merged with the specified region
	can_merge(other: ProcessMemoryRegion): bool {
		# Regions can not be merged if they have different inodes
		if not (inode == other.inode) return false

		# Regions can not be merged if they have different devices
		if not (device == other.device) return false

		# Regions can not be merged if they have different owners
		if not (owners == other.owners) return false

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
	# Summary: Stores the pid of the process that owns this memory
	pid: u32

	# Summary: Stores the allocator used by this structure
	allocator: Allocator

	# Summary: Sorted list of virtual memory mappings (smallest virtual address to largest).
	allocations: List<ProcessMemoryRegion>

	# Summary: Available virtual address regions by address (sorted)
	available_regions_by_address: List<Segment>

	# Summary: Stores the paging table used for configuring the virtual memory of the process.
	paging_table: PagingTable

	# Summary: Stores the kernel stack pointer
	kernel_stack_pointer: u64

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
		mapper.map_kernel(paging_table as u64*)

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

	init(other: ProcessMemory) {
		this.pid = other.pid
		this.allocator = other.allocator
		this.allocations = other.allocations
		this.available_regions_by_address = other.available_regions_by_address
		this.paging_table = other.paging_table
		this.kernel_stack_pointer = other.kernel_stack_pointer
		this.min_memory_map_address = other.min_memory_map_address
		this.break = other.break
		this.max_break = other.max_break
	}

	# Summary:
	# Inherits all the memory from the specified owners.
	# Basically just marks all regions as inherited from the specified owners.
	inherit(owners: MemoryRegionOwners) {
		# Mark all regions as inherited
		loop (i = 0, i < allocations.size, i++) {
			allocations[i].owners = owners
		}

		# Add this process to the owners
		owners.add(pid)
	}

	# Summary: Attempts to find a region that contains the specified address
	find_region(address: u64): Optional<ProcessMemoryRegion> {
		# Find the first region that contains the address
		# Todo: Later this could be optimized with binary search?
		index = allocations.find_index<u64>(
			address, 
			(i: ProcessMemoryRegion, address: u64) -> i.region.contains(address as link)
		)

		# If no region was found, return none
		if index == -1 return Optionals.empty<ProcessMemoryRegion>()

		# Return the region
		return Optionals.new<ProcessMemoryRegion>(allocations[index])
	}

	# Summary: Removes intersecting regions from the allocation list
	private remove_intersecting_allocations(allocation: ProcessMemoryRegion, deallocate_physical_pages: bool): _ {
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
			intersection = intersecting.region.intersection(region)

			# Check if the region is intersecting
			if intersection.size == 0 stop

			# Deallocate all physical pages inside the intersection if requested
			if deallocate_physical_pages {
				# Deallocate all pages in the specified virtual region
				loop (virtual_page = intersection.start, virtual_page < intersection.end, virtual_page += PAGE_SIZE) {
					if paging_table.to_physical_address(virtual_page as link) has not physical_page continue

					debug.write('Process memory: Deallocating physical page ') debug.write_address(physical_page) debug.write_line()

					# Reset the page configuration and deallocate the physical page
					require(paging_table.set_page_configuration(virtual_page, 0), 'Failed to reset page configuration')
					PhysicalMemoryManager.instance.deallocate_all(physical_page)
				}
			}

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
		# Todo: More generalized approach here is needed for checking whether the pages should be deallocated
		remove_intersecting_allocations(allocation, allocation.inode.has_value)

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
		internal_offset = (virtual_page - allocation.region.start) as u64

		if not allocation.inode.empty {
			debug.write_line('Process memory: Initializing physical page from inode')
			inode = allocation.inode.get_value()

			# Compute the offset where we should read
			offset = allocation.offset + internal_offset

			# Compute how many bytes should be read
			read_size = math.min(inode.size() - offset, PAGE_SIZE)

			# Initialize the contents of the page based on the inode
			inode.read_bytes(mapped_physical_page, offset, read_size)
			return
		}
	}

	# Summary: Returns whether the page of the specified virtual address is accessible
	is_accessible(virtual_address: link): bool {
		return not paging_table.to_physical_address(virtual_address).empty
	}

	# Summary: Returns whether the specified virtual region is accessible
	is_accessible(region: Segment): bool {
		# Verify all pages in the region are accessible
		# Note: Virtual region can be unaligned to pages
		start_page = memory.page_of(region.start)
		end_page = memory.round_to_page(region.end)

		loop (virtual_page = start_page, virtual_page < end_page, virtual_page += PAGE_SIZE) {
			if not is_accessible(virtual_page) return false
		}

		return true
	}

	# Summary: Returns whether the page at the specified virtual address is used by other owners.
	is_page_used_by_other_owners(region: ProcessMemoryRegion, virtual_address: u64): bool {
		require(region.owners !== none, 'Missing region owners')

		loop (i = 0, i < region.owners.pids.size, i++) {
			owner_pid = region.owners.pids[i]

			# Only look at other owners 
			if owner_pid == pid continue

			require(interrupts.scheduler.find(owner_pid) has owner, 'Missing owner process')

			# Find the region from the owner that contains the virtual address.
			# If the region also has the same owners, the region is used by the owner.
			if owner.memory.find_region(virtual_address) has owner_region and owner_region.owners === region.owners return true
		}

		return false
	}

	process_copy_on_write(region: ProcessMemoryRegion, virtual_address: u64, configuration: u64): bool {
		debug.write_line('Process memory: Processing copy-on-write page fault')
		panic('Todo: Remove')

		# If the accessed page is used by other owners, we really need to copy
		if is_page_used_by_other_owners(region, virtual_address) {
			# Attempt to allocate a physical page for the virtual page
			new_physical_page = PhysicalMemoryManager.instance.allocate_physical_region(PAGE_SIZE)
			if new_physical_page === none return false

			# Extract the physical page that is used by other owners
			old_physical_page = mapper.address_from_page_entry(configuration)

			# Copy bytes from the shared page to the new page
			mapped_destination_page = mapper.map_kernel_page(new_physical_page)
			mapped_source_page = mapper.map_kernel_page(old_physical_page)
			memory.copy(mapped_destination_page, mapped_source_page, PAGE_SIZE)

			# Place the new physical page in to the configuration
			configuration = mapper.set_address(configuration, new_physical_page)
			paging_table.set_page_configuration(virtual_address as link, configuration)
			return true
		}

		# Because the accessed page is not used by others, we can just take it
		paging_table.set_page_configuration(virtual_address as link, configuration | mapper.PAGE_CONFIGURATION_WRITABLE)
		return true
	}

	# Summary: Returns whether the specified page is "copy-on-write"
	is_copy_on_write_region(region: ProcessMemoryRegion, configuration: u64): bool {
		# If there are not multiple owners, this region can not be "copy-on-write"
		if region.owners === none return false

		# Ensure the page configuration is present and is set to non-writable
		return mapper.is_present(configuration) and not mapper.is_writable(configuration)
	}

	# Summary:
	# Processes page fault at the specified address.
	# If the specified address is in an allocated page that is accessible for 
	# the process, the page is mapped and this function returns true.
	# Otherwise if the specified address is not accessible, 
	# this function returns false.
	# Todo: It is kinda weird that we pass the process as this object should know about its owner, but we only have the pid and it is inefficent to lookup the process...
	process_page_fault(process: Process, virtual_address: u64, write: bool): bool {
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

		# Align the virtual address to pages, so we know which page to map
		virtual_page: link = (virtual_address & (-PAGE_SIZE)) as link

		# Retrieve the current configuration for the accessed page
		configuration = paging_table.get_page_configuration(virtual_address as link)

		if is_copy_on_write_region(allocation, configuration) {
			require(write, 'Copy-on-write page caused page fault without writing')

			if not process_copy_on_write(allocation, virtual_address, configuration) return false

			# Mark the accessed page so that it is no longer owned by others
			allocate_specific_region(allocation.slice(virtual_page, virtual_page + PAGE_SIZE))
			return true
		}

		# Todo: Verify access rights here?

		# If the allocation maps a device, let the device do the mapping if it wants
		if allocation.device has device {
			debug.write_line('Process memory: Attempting to use device for resolving page fault')

			# Attempt to map using the device
			if device.map(process, allocation, virtual_address) has result {
				debug.write_line('Process memory: Page fault resolved using device')
				return result == 0
			}
		}

		# Attempt to allocate a physical page for the virtual page
		physical_page = PhysicalMemoryManager.instance.allocate_physical_region(PAGE_SIZE)
		if physical_page === none return false

		# Initialize the contents of the accessed page
		initialize_physical_page(allocation, virtual_page, physical_page)

		# Map the new physical page to the accessed virtual page and continue as normal
		if process.is_kernel_process {
			paging_table.map_page(allocator, virtual_page, physical_page)
		} else {
			paging_table.map_page(allocator, virtual_page, physical_page, MAP_USER)
		}

		return true
	}

	# Summary: Deallocates all programs allocations and removes them from the allocation list
	deallocate_program_allocations() {
		loop (i = allocations.size - 1, i >= 0, i--) {
			# Skip runtime allocations
			region = allocations[i].region
			# if region.type != PROCESS_ALLOCATION_PROGRAM_TEXT and region.type != PROCESS_ALLOCATION_PROGRAM_DATA continue

			# Deallocate the program allocation and remove it from the allocations
			debug.write('Process memory: Deallocating ') region.print() debug.write_line()

			deallocate(region)
		}

		# Reset the break as well
		break = 0
	}
 
	# Summary: Deallocates the specified region allowing fragmentation
	deallocate(virtual_region: Segment): i64 {
		# Validate the specified region before doing anything with it
		require(virtual_region.start % PAGE_SIZE == 0 and virtual_region.size % PAGE_SIZE == 0, 'Virtual region was not aligned')
		print_allocations()

		# Empty regions can not be deallocated
		if virtual_region.size == 0 return EINVAL

		# Deallocate all the allocations inside the specified virtual region
		remove_intersecting_allocations(ProcessMemoryRegion.new(virtual_region), true)

		# Add virtual region back to available regions
		memory.sorted.insert<Segment>(
			available_regions_by_address,
			virtual_region,
			(a: Segment, b: Segment) -> (a.start - b.start) as i64
		)

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