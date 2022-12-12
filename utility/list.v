List<T> {
	allocator: Allocator
	elements: T*
	capacity: u64
	size: u64

	init(allocator: Allocator) {
		this.allocator = allocator
		this.elements = none as T*
		this.capacity = 0
		this.size = 0
	}

	init(allocator: Allocator, capacity: u64, fill: bool) {
		this.allocator = allocator
		this.elements = allocator.allocate(sizeof(T) * capacity)
		this.capacity = capacity

		if fill { this.size = capacity }
	}

	private extend() {
		# Allocate more memory for elements
		new_capacity = math.max(size, 1) * 2
		new_elements = allocator.allocate(sizeof(T) * new_capacity)

		# Copy the current elements to the allocated memory
		memory.copy(new_elements, elements, sizeof(T) * size)

		# Deallocate the old memory
		allocator.deallocate(elements)

		elements = new_elements
		capacity = new_capacity
	}

	private shrink() {
		# Do nothing if the list has not shrunk enough
		half = capacity / 2
		if size >= half return

		if size == 0 {
			allocator.deallocate(elements)
			elements = none
			capacity = 0
			size = 0
			return
		}

		new_capacity = half
		new_elements = allocator.allocate(sizeof(T) * new_capacity)

		# Copy the current elements to the allocated memory
		memory.copy(new_elements, elements, sizeof(T) * size)

		# Deallocate the old memory
		allocator.deallocate(elements)

		elements = new_elements
		capacity = new_capacity
	}

	add(element: T) {
		if size >= capacity extend()

		elements[size] = element
		size++
	}

	remove_at(i: u64) {
		require(i >= 0 and i < size, 'Index out of bounds')

		destination = elements + sizeof(T) * i
		source = destination + sizeof(T)
		memory.copy(destination, source, (size - i - 1) * sizeof(T))

		# Zero out the moved last element for safety
		memory.zero(elements + (size - 1) * sizeof(T), sizeof(T))

		size--
		shrink()
	}

	get(i: u64): T {
		require(i >= 0 and i < size, 'Index out of bounds')
		return elements[i]
	}

	set(i: u64, element: T) {
		require(i >= 0 and i < size, 'Index out of bounds')
		elements[i] = element
	}
}