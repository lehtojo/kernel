Allocator {
	open allocate(bytes: u64): link
	open deallocate(address: link)

	allocate<T>(): T* {
		return allocate(sizeof(T))
	}

	copy(source: link, size: u64): link {
		result = allocate(size)
		memory.copy(result, source, size)
		return result
	}
}

Allocator BufferAllocator {
	position: link
	end: link

	init(buffer: link, size: u64) {
		position = buffer
		end = buffer + size
	}

	override allocate(bytes: u64) {
		if position + bytes > end {
			panic('Buffer allocator out of memory')
			return none as link
		}

		result = position
		position += bytes

		memory.zero(result, bytes)

		return result
	}

	override deallocate(address: link) {
		# Deallocation is not supported
	}
}

Allocator LocalHeapAllocator {
	private allocator: Allocator
	private allocations: List<link>

	init(allocator: Allocator) {
		this.allocator = allocator
		this.allocations = List<link>(allocator) using allocator
	}

	override allocate(bytes: u64) {
		allocation = allocator.allocate(bytes)
		if allocation !== none allocations.add(allocation)
		
		return allocation
	}

	override deallocate(address: link) {
		loop (i = 0, i < allocations.size, i++) {
			if allocations[i] !== address continue

			allocations.remove_at(i)
			allocator.deallocate(address)
			return
		}

		panic('Allocator did not own the address to be deallocated')
	}

	deallocate() {
		loop (i = 0, i < allocations.size, i++) {
			allocator.deallocate(allocations[i])
		}
	}

	destruct() {
		deallocate()
		allocator.deallocate(this as link)
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
