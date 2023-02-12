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
