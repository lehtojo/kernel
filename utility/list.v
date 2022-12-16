List<T> {
	allocator: Allocator
	data: T*
	capacity: u64
	size: u64

	init(allocator: Allocator) {
		this.allocator = allocator
		this.data = none as T*
		this.capacity = 0
		this.size = 0
	}

	init(allocator: Allocator, capacity: u64, fill: bool) {
		this.allocator = allocator
		this.data = allocator.allocate(sizeof(T) * capacity)
		this.capacity = capacity

		if fill { this.size = capacity }
	}

	private extend() {
		reserve(math.max(size, 1) * 2)
	}

	private shrink() {
		# Do nothing if the list has not shrunk enough
		half = capacity / 2
		if size >= half return

		if size == 0 {
			allocator.deallocate(data)
			data = none
			capacity = 0
			size = 0
			return
		}

		new_capacity = half
		new_data = allocator.allocate(sizeof(T) * new_capacity)

		# Copy the current data to the allocated memory
		memory.copy(new_data, data, sizeof(T) * size)

		# Deallocate the old memory
		allocator.deallocate(data)

		data = new_data
		capacity = new_capacity
	}

	reserve(reservation: u64) {
		if reservation <= capacity return

		# Allocate more memory for data
		new_data = allocator.allocate(sizeof(T) * reservation)

		# Copy the current data to the allocated memory
		memory.copy(new_data, data, sizeof(T) * size)

		# Deallocate the old memory
		allocator.deallocate(data)

		data = new_data
		capacity = reservation
	}

	add(element: T) {
		if size >= capacity extend()

		data[size] = element
		size++
	}

	insert(i: u64, element: T) {
		require(i >= 0 and i < size, 'Index out of bounds')

		if size >= capacity extend()

		source = data + sizeof(T) * i
		destination = source + sizeof(T)
		bytes = sizeof(T) * (size - i)
		memory.copy(destination, source, bytes)

		data[i] = element
		size++
	}

	remove_at(i: u64) {
		require(i >= 0 and i < size, 'Index out of bounds')

		destination = data + sizeof(T) * i
		source = destination + sizeof(T)
		memory.copy(destination, source, (size - i - 1) * sizeof(T))

		# Zero out the moved last element for safety
		memory.zero(data + (size - 1) * sizeof(T), sizeof(T))

		size--
		shrink()
	}

	get(i: u64): T {
		require(i >= 0 and i < size, 'Index out of bounds')
		return data[i]
	}

	set(i: u64, element: T) {
		require(i >= 0 and i < size, 'Index out of bounds')
		data[i] = element
	}
}