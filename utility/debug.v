namespace debug

booted: bool

export write_bytes(data: link, size: u64) {
	# Redirect to boot console device when it is initialized
	if not booted and BootConsoleDevice.instance !== none {
		BootConsoleDevice.instance.write_raw(data, size)
		#return
	}

	serial.write(data, size)
}

export next_line() {
	# Redirect to boot console device when it is initialized
	if not booted and BootConsoleDevice.instance !== none {
		BootConsoleDevice.instance.write_raw('\n', 1)
		#return
	}

	serial.put(`\n`)
}

# Summary: Writes the specified character to the console
export put(value: char) {
	# Redirect to boot console device when it is initialized
	if not booted and BootConsoleDevice.instance !== none {
		data: char[1]
		data[] = value
		BootConsoleDevice.instance.write_raw(data, 1)
		#return
	}
	
	serial.put(value)
}

# Summary: Writes the specified string to the console
export write(string: String) {
	write_bytes(string.data, string.length)
}

# Summary: Writes the specified string to the console
export write(string: link) {
	write_bytes(string, length_of(string))
}

# Summary: Writes the specified number of characters from the specified string
export write(string: link, length: large) {
	write_bytes(string, length)
}

# Summary: Writes the specified integer to the console
export write(value: large) {
	buffer: byte[32]
	memory.zero(buffer as link, 32)
	length = to_string(value, buffer as link)
	write_bytes(buffer as link, length)
}

# Summary: Writes the specified integer to the console
export write(value: normal) { write(value as large) }

# Summary: Writes the specified integer to the console
export write(value: small) { write(value as large) }

# Summary: Writes the specified integer to the console
export write(value: tiny) { write(value as large) }

# Summary: Writes the specified decimal to the console
export write(value: decimal) {
	buffer: byte[64]
	memory.zero(buffer as link, 64)
	length = to_string(value, buffer as link)
	write(buffer as link, length)
}

# Summary: Writes the specified bool to the console
export write(value: bool) {
	if value {
		write('true', 4)
	} else {
		write('false', 5)
	}
}

# Summary: Writes the specified address to the console
export write_address(value) {
	buffer: byte[32]
	memory.zero(buffer as link, 32)
	length = to_hexadecimal(value, buffer as link)
	write_bytes('0x', 2)
	write_bytes(buffer as link, length)
}

# Summary: Writes the specified string to the console
export write_line(string: String) {
	write_bytes(string.data, string.length)
	next_line()
}

# Summary: Writes the specified string to the console
export write_line(string: link) {
	write_bytes(string, length_of(string))
	next_line()
}

# Summary: Writes the specified number of characters from the specified string
export write_line(string: link, length: large) {
	write_bytes(string, length)
	next_line()
}

# Summary: Writes the specified integer to the console
export write_line(value: large) {
	buffer: byte[32]
	memory.zero(buffer as link, 32)
	length = to_string(value, buffer as link)
	write_bytes(buffer as link, length)
	next_line()
}

# Summary: Writes the specified integer to the console
export write_line(value: normal) { write_line(value as large) }

# Summary: Writes the specified integer to the console
export write_line(value: small) { write_line(value as large) }

# Summary: Writes the specified integer to the console
export write_line(value: tiny) { write_line(value as large) }

# Summary: Writes the specified decimal to the console
export write_line(value: decimal) {
	buffer: byte[64]
	memory.zero(buffer as link, 64)
	length = to_string(value, buffer as link)
	write(buffer as link, length)
	next_line()
}

# Summary: Writes the specified bool to the console
export write_line(value: bool) {
	if value {
		write('true', 4)
	}
	else {
		write('false', 5)
	}

	next_line()
}

# Summary: Writes the specified strings to the console
export write_line(strings: List<String>) {
	separator = ''

	loop (i = 0, i < strings.size, i++) {
		write(separator)
		write(strings[i])
		separator = ', '
	}

	next_line()
}

# Summary: Writes an empty line to the console
export write_line() {
	next_line()
}