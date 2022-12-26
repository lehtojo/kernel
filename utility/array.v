plain Array<T> {
	data: T*
	size: u64

	init(data: T*, size: u64) {
		this.data = data
		this.size = size
	}

	set(i: u64, element: T) {
		require(i >= 0 and i < size, 'Index out of bounds')
		data[i] = element
	}

	get(i: u64): T {
		require(i >= 0 and i < size, 'Index out of bounds')
		return data[i]
	}
}