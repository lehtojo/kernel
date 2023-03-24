none = 0

allocate(bytes: i64) {
	return none as link
}

deallocate(address: link) {

}

internal_is(a: link, b: link) {
	return false
}

init() {}

require(condition: bool, error: link) {
	if not condition panic(error)
}

panic(error: link) {
	debug.write('KERNEL PANIC :^( --- ')
	debug.write_line(error)
	loop {}
}

namespace memory

namespace sorted {
	# Summary: Inserts the specified element into the sorted list
	insert<T>(elements: List<T>, element: T, comparator: (T, T) -> i64) {
		start = 0
		end = elements.size

		loop (end - start > 0) {
			middle = (start + end) / 2
			comparison = comparator(element, elements[middle])

			# Stop if the element can be added at the middle
			if comparison == 0 {
				start = middle
				stop
			}

			if comparison > 0 {
				# The specified element must be after the middle element, so it must be inserted within middle..end
				start = middle + 1
			} else {
				# The specified element must be before the middle element, so it must be inserted within start..middle
				end = middle
			}
		}

		elements.insert(start, element)
	}

	# Summary: Finds an element from the sorted list using the specified comparator
	find_index<T, U>(elements: List<T>, data: U, comparator: (T, U) -> i64): i64 {
		start = 0
		end = elements.size

		loop (end - start > 0) {
			middle = (start + end) / 2

			comparison = comparator(elements[middle], data)

			if comparison > 0 {
				# The wanted must be after the middle element, so it must be inserted within middle..end
				start = middle + 1
			} else comparison < 0 {
				# The wanted must be before the middle element, so it must be inserted within start..middle
				end = middle
			} else {
				# We found the wanted element
				return middle
			}
		}

		return -1
	}
}

# Summary: Returns whether the contents of the specified memory addresses are equal
compare(a: link, b: link, size: u64): bool {
	if size === 0 return true

	loop (i = 0, i < size, i++) {
		if a[i] !== b[i] return false
	}

	return true
}

# Summary: Finds the index of specified byte in the specified memory address
index_of(address: link, value: u8) {
	loop (address[] !== value, address++) {}
	return address
}

# Summary: Reverses the bytes in the specified memory range
export reverse(memory: link, size: large) {
	i = 0
	j = size - 1
	n = size / 2

	loop (i < n) {
		temporary = memory[i]
		memory[i] = memory[j]
		memory[j] = temporary

		i++
		j--
	}
}

copy(destination: link, source: link, size: u64) {
	if destination <= source {
		loop (i = 0, i < size, i++) {
			destination[] = source[]
			destination++
			source++
		}
	} else {
		destination += size - 1
		source += size - 1

		loop (i = 0, i < size, i++) {
			destination[] = source[]
			destination--
			source--
		}
	}
}

copy_into(destination, destination_offset, source, source_offset, size) {
	copy(destination.data + destination_offset, source.data + source_offset, size)
}

zero(address: link, size: u64) {
	loop (i = 0, i < size, i++) {
		address[i] = 0
	}
}

round_to(address, alignment) {
	return (address + alignment - 1) & (-alignment)
}

round_to_page(address) {
	return (address + PAGE_SIZE - 1) & (-PAGE_SIZE)
}

is_aligned(address, alignment): bool {
	return (address & (-alignment)) == address
}