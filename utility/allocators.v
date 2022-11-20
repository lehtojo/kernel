Allocator {
	open allocate(bytes: u64): link
	open deallocate(address: link)

	new<T>(): T {
		return allocate(capacityof(T)) as T
	}
}

Allocator StaticAllocator {
	override allocate(bytes: u64) {

	}

	override deallocate(address: link) {
		# Static allocator can not deallocate
	}
}

