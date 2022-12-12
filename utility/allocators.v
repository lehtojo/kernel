Allocator {
	open allocate(bytes: u64): link
	open deallocate(address: link)
}

Allocator StaticAllocator {
	shared instance: StaticAllocator

	shared initialize() {
		instance = StaticAllocator() using 0x190000
	}

	position: link
	end: link

	init() {
		position = this as link + capacityof(StaticAllocator)
		end = position + 1000000
	}

	override allocate(bytes: u64) {
		debug.write('Allocating static memory ')
		debug.write(bytes)
		debug.write_line(' bytes')

		require(position + bytes <= end, 'Out of static memory')
		result = position
		position += bytes

		debug.write('Static memory allocated: ')
		debug.write_line((position - (this as link + capacityof(StaticAllocator))) as u64)

		return result
	}

	override deallocate(address: link) {
		# Static allocator can not deallocate
	}
}

PageAllocatorAvailablePage {
	next: PageAllocatorAvailablePage
}

PageAllocator {
	constant MIN_EXTEND_PAGES = 0x100

	position: link
	obstacles: List<Segment>

	next: PageAllocatorAvailablePage   # Next available page
	last: PageAllocatorAvailablePage   # Last available page
	available: u64                     # Number of available pages

	init(position: link) {
		this.position = position
	}

	extend(pages: i32) {
		# TODO: Detect overlaps with the obstacles and maybe split into recursive extend calls

		page = position

		loop (i = 0, i < pages, i++) {
			add_available_page(page)
			page += PAGE_SIZE
		}

		position = page
	}

	add_available_page(address: link) {
		page = address as PageAllocatorAvailablePage
		page.next = none as PageAllocatorAvailablePage

		if next !== none {
			next.next = page
		} else {
			next = page
		}

		last = page
		available++
	}

	take_next(): link {
		if next === none return none as link

		result = next
		next = result.next

		# Update the last available page to none if we have used all the pages
		if next === none { last = none as link }

		return result
	}

	allocate(bytes: u64, virtual_address: link) {
		require(((virtual_address as u64) & (PAGE_SIZE - 1)) == 0, 'Virtual address was not aligned correctly')

		# Round up the number of bytes to the next page
		bytes = ((bytes + PAGE_SIZE - 1) & (!PAGE_SIZE))
		pages = bytes / PAGE_SIZE
		require(pages <= 10000, 'Too large allocation received (debug safety check)')

		# Allocate more memory when necessary
		if pages > available {
			extend(math.max(pages, MIN_EXTEND_PAGES)) # TODO: Verify error handling
		}

		loop (i = 0, i < pages, i++) {
			next = take_next()
			require(next !== none, 'Next available page is none even though it should not be')

			# Map the available page to the current virtual address and move to the next page
			allocator.map_page(virtual_address, next)
			virtual_address += PAGE_SIZE
		}
	}

	deallocate(address: link) {
		require(((address as u64) & (PAGE_SIZE - 1)) == 0, 'Illegal page deallocation')

		
	}
}
