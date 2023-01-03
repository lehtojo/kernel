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

constant PAGING_TABLE_ENTRY_COUNT = 512

plain PagingTable {
	entries: u64[PAGING_TABLE_ENTRY_COUNT]

	# Summary:
	# Maps the specified physical address to the specified virtual address.
	# If the entries required to map the address do not exist,
	# this function allocates them using the specified allocator.
	map_page(allocator: Allocator, virtual_address: link, physical_address: link) {
		require((virtual_address % PAGE_SIZE) == 0, 'Virtual address was not aligned correctly')
		require((physical_address % PAGE_SIZE) == 0, 'Physical address was not aligned correctly')

		debug.write('Mapping virtual page ')
		debug.write_address(virtual_address)
		debug.write(' to physical page ')
		debug.write_address(physical_address)
		debug.write_line()

		# Virtual address: [L4 9 bits] [L3 9 bits] [L2 9 bits] [L1 9 bits] [Offset 12 bits]
		l1_index: u32 = (virtual_address |> 12) & 0b111111111
		l2_index: u32 = (virtual_address |> 21) & 0b111111111
		l3_index: u32 = (virtual_address |> 30) & 0b111111111
		l4_index: u32 = (virtual_address |> 39) & 0b111111111

		l1 = none as PagingTable
		l2 = none as PagingTable
		l3 = none as PagingTable
		l4 = none as PagingTable

		# Load the L4 paging table
		entry = entries[l4_index]

		if mapper.is_present(entry) {
			# Load the paging table from entry 
			l4 = mapper.virtual_address_from_page_entry(entry) as PagingTable
		} else {
			# Create the paging table for the entry
			l4 = PagingTable() using allocator
			l4_physical_address = mapper.to_physical_address(l4 as link)
			debug.write('Paging: Allocated L4 table ')
			debug.write_address(l4 as link)
			debug.write(' at physical address ')
			debug.write_address(l4_physical_address)
			debug.write_line()

			entry_address = entries + l4_index * sizeof(u64)

			mapper.set_address(entry_address, l4_physical_address)
			mapper.set_writable(entry_address)
			mapper.set_present(entry_address)
		}

		# Load the L3 paging table
		entry = l4.entries[l3_index]

		if mapper.is_present(entry) {
			# Load the paging table from entry 
			l3 = mapper.virtual_address_from_page_entry(entry) as PagingTable
		} else {
			# Create the paging table for the entry
			l3 = PagingTable() using allocator
			l3_physical_address = mapper.to_physical_address(l3 as link)
			debug.write('Paging: Allocated L3 table ')
			debug.write_address(l3 as link)
			debug.write(' at physical address ')
			debug.write_address(l3_physical_address)
			debug.write_line()

			entry_address = l4.entries + l3_index * sizeof(u64)

			mapper.set_address(entry_address, l3_physical_address)
			mapper.set_writable(entry_address)
			mapper.set_present(entry_address)
		}

		# Load the L2 paging table
		entry = l3.entries[l2_index]

		if mapper.is_present(entry) {
			# Load the paging table from entry 
			l2 = mapper.virtual_address_from_page_entry(entry) as PagingTable
		} else {
			# Create the paging table for the entry
			l2 = PagingTable() using allocator
			l2_physical_address = mapper.to_physical_address(l2 as link)
			debug.write('Paging: Allocated L2 table ')
			debug.write_address(l2 as link)
			debug.write(' at physical address ')
			debug.write_address(l2_physical_address)
			debug.write_line()

			entry_address = l3.entries + l2_index * sizeof(u64)

			mapper.set_address(entry_address, l2_physical_address)
			mapper.set_writable(entry_address)
			mapper.set_present(entry_address)
		}

		# Point the L1 entry to the specified physical address
		entry = l2.entries[l1_index]
		entry_address = l2.entries + l1_index * sizeof(u64)

		mapper.set_address(entry_address, physical_address)
		mapper.set_writable(entry_address)
		mapper.set_present(entry_address)
	}

	# Summary: Maps all the pages in the specified memory region.
	map_region(allocator: Allocator, mapping: MemoryMapping) {
		virtual_address = mapping.virtual_address_start as link
		physical_address = mapping.physical_address_start as link

		virtual_address_end = virtual_address + mapping.size

		loop (virtual_address < virtual_address_end) {
			map_page(allocator, virtual_address, physical_address)

			virtual_address += PAGE_SIZE
			physical_address += PAGE_SIZE
		}
	}

	# Summary: Returns the physical address to which the specified virtual address is mapped.
	to_physical_address(virtual_address: link): Optional<link> {
		offset = virtual_address & 0xFFF

		# Virtual address: [L4 9 bits] [L3 9 bits] [L2 9 bits] [L1 9 bits] [Offset 12 bits]
		l1_index: u32 = (virtual_address |> 12) & 0b111111111
		l2_index: u32 = (virtual_address |> 21) & 0b111111111
		l3_index: u32 = (virtual_address |> 30) & 0b111111111
		l4_index: u32 = (virtual_address |> 39) & 0b111111111

		# Load the L4 paging table
		entry = entries[l4_index]
		if not mapper.is_present(entry) return Optionals.empty<link>()

		l4 = mapper.virtual_address_from_page_entry(entry) as PagingTable

		# Load the L3 paging table
		entry = l4.entries[l3_index]
		if not mapper.is_present(entry) return Optionals.empty<link>()

		l3 = mapper.virtual_address_from_page_entry(entry) as PagingTable

		# Load the L2 paging table
		entry = l3.entries[l2_index]
		if not mapper.is_present(entry) return Optionals.empty<link>()

		l2 = mapper.virtual_address_from_page_entry(entry) as PagingTable

		# Load the L1 entry
		entry = l2.entries[l1_index]
		if not mapper.is_present(entry) return Optionals.empty<link>()

		physical_address = mapper.address_from_page_entry(entry) + offset
		return Optionals.new<link>(physical_address as link)
	}

	# Summary: Deallocates this layer and its child tables using the specified allocator
	dispose(allocator: Allocator, layer: u32) {
		require(layer >= 0, 'Illegal layer number passed to paging table upon disposal')

		# If we are at the bottom, the entries no longer point to structures that can be deallocated
		if layer == 0 return

		loop (i = 0, i < PAGING_TABLE_ENTRY_COUNT, i++) {
			entry = entries[i]
			if not mapper.is_present(entry) continue

			# Dispose the table, its tables and so on until the bottom layer is reached 
			table = mapper.virtual_address_from_page_entry(entry) as PagingTable
			table.dispose(layer - 1)
		}

		# Since all the child tables have been deallocated, this table is no longer needed and thus it can be deallocated
		allocator.deallocate(this)
	}
}