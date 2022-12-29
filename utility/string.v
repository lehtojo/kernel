pack String {
	data: link
	length: u64

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