namespace kernel.serial

constant COM1 = 0x3F8

export initialize() {
	ports.write_u8(COM1 + 1, 0x00)
	ports.write_u8(COM1 + 3, 0x80)
	ports.write_u8(COM1 + 0, 0x02)
	ports.write_u8(COM1 + 1, 0x00)
	ports.write_u8(COM1 + 3, 0x03)
	ports.write_u8(COM1 + 2, 0xC7)
	ports.write_u8(COM1 + 4, 0x0B)
}

export is_transmit_empty() {
	return (ports.read_u8(COM1 + 5) & 0x20) != 0
}

export write(memory: link, size: u32) {
	loop (not is_transmit_empty()) {}

	loop (i = 0, i < size, i++) {
		ports.write_u8(COM1, memory[i])
	}
}

export write(string: link): _ {
	write(string, length_of(string))
}

export put(character: char) {
	loop (not is_transmit_empty()) {}
	ports.write_u8(COM1, character)
}