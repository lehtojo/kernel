List<T> {
	allocator: Allocator
	data: T*
	capacity: u64
	size: u64
	bounds => Range.new(0, size)

	init(allocator: Allocator) {
		this.allocator = allocator
		this.data = none as T*
		this.capacity = 0
		this.size = 0
	}

	init(allocator: Allocator, capacity: u64, fill: bool) {
		this.allocator = allocator
		this.data = allocator.allocate(strideof(T) * capacity)
		this.capacity = capacity
		this.size = 0

		if fill { this.size = capacity }
	}

	init(allocator: Allocator, data: T*, size: u64) {
		this.allocator = allocator
		this.data = data
		this.size = size
		this.capacity = size
	}

	init(allocator: Allocator, other: List<T>) {
		this.allocator = allocator
		this.data = allocator.allocate(strideof(T) * other.capacity)
		this.capacity = other.capacity
		this.size = other.size

		memory.copy(data, other.data, strideof(T) * size)
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
			data = none as T*
			capacity = 0
			size = 0
			return
		}

		new_capacity = half
		new_data = allocator.allocate(strideof(T) * new_capacity)

		# Copy the current data to the allocated memory
		memory.copy(new_data, data, strideof(T) * size)

		# Deallocate the old memory
		if data !== none {
			allocator.deallocate(data)
		}

		data = new_data
		capacity = new_capacity
	}

	reserve(reservation: u64) {
		if reservation <= capacity return

		# Allocate more memory for data
		new_data = allocator.allocate(strideof(T) * reservation)

		# Deallocate the old memory
		if data !== none {
			# Copy the current data to the allocated memory
			memory.copy(new_data, data, strideof(T) * size)

			allocator.deallocate(data)
		}

		data = new_data
		capacity = reservation
	}

	add(element: T) {
		if size >= capacity extend()

		data[size] = element
		size++
	}

	insert(i: u64, element: T) {
		require(i >= 0 and i <= size, 'Index out of bounds')

		if size >= capacity extend()

		source = data + strideof(T) * i
		destination = source + strideof(T)
		bytes = strideof(T) * (size - i)
		memory.copy(destination, source, bytes)

		data[i] = element
		size++
	}

	remove(element: T): bool {
		i = index_of(element)
		if i < 0 return false

		remove_at(i)
		return true
	}

	remove_at(i: u64) {
		require(i >= 0 and i < size, 'Index out of bounds')

		destination = data + strideof(T) * i
		source = destination + strideof(T)
		memory.copy(destination, source, (size - i - 1) * strideof(T))

		# Zero out the moved last element for safety
		memory.zero(data + (size - 1) * strideof(T), strideof(T))

		size--
		shrink()
	}

	remove_all(start: u64, end: u64): _ {
		require(start >= 0 and start <= size, 'Start index out of bounds')
		require(end >= 0 and end <= size, 'End index out of bounds')
		require(start <= end, 'Start index must be less than or equal to end index')
		
		count = end - start
		if count == 0 return

		destination = data + strideof(T) * start
		source = data + strideof(T) * end
		memory.copy(destination, source, count * strideof(T))

		# Zero out the moved last elements for safety
		memory.zero(data + (size - count) * strideof(T), strideof(T) * count)

		size -= count
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

	index_of(element: T): i64 {
		loop (i = 0, i < size, i++) {
			if data[i] == element return i
		}

		return -1
	}

	find_index(filter: (T) -> bool): i64 {
		loop (i = 0, i < size, i++) {
			if filter(data[i]) return i
		}

		return -1
	}

	find_index<U>(data: U, filter: (T, U) -> bool): i64 {
		loop (i = 0, i < size, i++) {
			if filter(this.data[i], data) return i
		}

		return -1
	}

	find_last_index(filter: (T) -> bool): i64 {
		loop (i = size - 1, i >= 0, i--) {
			if filter(data[i]) return i
		}

		return -1
	}

	find_last_index<U>(data: U, filter: (T, U) -> bool): i64 {
		loop (i = size - 1, i >= 0, i--) {
			if filter(this.data[i], data) return i
		}

		return -1
	}

	clear() {
		if data !== none {
			allocator.deallocate(data)
		}

		data = none as T*
		capacity = 0
		size = 0
	}

	destruct(allocator: Allocator): _ {
		clear()
		allocator.deallocate(this as link)
	}

	destruct(): _ {
		destruct(allocator)
	}
}