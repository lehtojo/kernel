Allocator {
	open allocate(bytes: u64): link
	open deallocate(address: link)
}

Allocator StaticAllocator {
	shared instance: StaticAllocator

	shared initialize() {
		instance = StaticAllocator() using 0x100000
	}

	position: link
	end: link

	init() {
		position = this as link + capacityof(StaticAllocator)
		end = position + 1000000
	}

	override allocate(bytes: u64) {
		require(position + bytes <= end, 'Out of static memory')
		result = position
		position += bytes
		return result
	}

	override deallocate(address: link) {
		# Static allocator can not deallocate
	}
}

