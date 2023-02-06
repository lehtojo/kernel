pack String {
	data: link
	length: u64

	shared empty(): String {
		return pack { data: none as link, length: 0 } as String
	}

	shared new(data: link): String {
		return pack { data: data, length: length_of(data) } as String
	}

	shared new(data: link, length: u64): String {
		return pack { data: data, length: length } as String
	}

	# Summary: Overrides the indexed accessor, returning the character in the specified position
	get(i: large) {
		require(i >= 0 and i <= length, 'Invalid getter index')
		return data[i]
	}

	# Summary: Returns the index of the first occurrence of the specified character starting from the specified offset
	index_of(character: char, offset: u64): i64 {
		require(offset <= length, 'Invalid offset')

		loop (i = offset, i < length, i++) {
			if data[i] == character return i
		}

		return -1
	}

	# Summary: Returns the index of the first occurrence of the specified character
	index_of(character: char): i64 {
		return index_of(character, 0)
	}

	# Summary: Returns the substring in the specified range
	slice(start: u64, end: u64): String {
		require(start <= end and start >= 0 and end <= length, 'Invalid slice range')
		return String.new(data + start, end - start)
	}

	# Summary: Returns the substring starting from the specified offset
	slice(start: u64): String {
		require(start >= 0 and start <= length, 'Invalid slice range')
		return String.new(data + start, length - start)
	}

	# Summary: Returns whether the two strings are equal
	equals(other: String): bool {
		a = length
		b = other.length

		if a != b return false

		loop (i = 0, i < a, i++) {
			if data[i] != other.data[i] return false
		}

		return true
	}

	# Summary: Returns whether the two strings are equal
	equals(other: link) {
		a = length
		b = length_of(other)

		if a != b return false

		loop (i = 0, i < a, i++) {
			if data[i] != other[i] return false
		}

		return true
	}

	# Summary: Computes hash code for the string
	hash() {
		hash = 5381
		a = length

		loop (i = 0, i < a, i++) {
			hash = ((hash <| 5) + hash) + data[i] # hash = hash * 33 + data[i]
		}

		return hash
	}
}