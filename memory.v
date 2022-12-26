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

zero(address: link, size: u64) {
	loop (i = 0, i < size, i++) {
		address[i] = 0
	}
}

align(address, alignment) {
	return (address + alignment - 1) & (-alignment)
}