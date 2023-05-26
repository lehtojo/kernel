plain MemoryRegion {
	readable address: link
	readable position: u64 = 0
	readable size: u64

	init(address: link, size: u64) {
		this.address = address
		this.size = size
	}

	advance(bytes: u64): bool {
		if position + bytes > size {
			position = size
			return false
		}

		position += bytes
		return true
	}

	write_string(string: String, terminate: bool) {
		# Verify we do not write outside of bounds
		if position + string.length + terminate >= size return false

		memory.copy(address + position, string.data, string.length)

		# Zero terminate the string if requested
		if terminate { address[position + string.length] = 0 }

		return true
	}

	write_memory<T>(value: T): bool {
		# Verify we do not write outside of bounds
		if position + sizeof(T) >= size return false
		memory.copy(address + position, value as link, sizeof(T))
		return true
	}

	write<T>(value: T): bool {
		# Verify we do not write outside of bounds
		if position + sizeof(T) >= size return false
		(address + position).(T*)[] = value
		return true
	}

	write_memory_and_advance<T>(value: T): bool {
		if not write_memory<T>(value) return false

		position += sizeof(T)
		return true
	}

	write_and_advance<T>(value: T): bool {
		if not write<T>(value) return false

		position += sizeof(T)
		return true
	}

	write_string_and_advance(string: String, terminate: bool) {
		if not write_string(string, terminate) return false

		position += string.length + terminate
		return true
	}
}