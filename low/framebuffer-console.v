namespace kernel.low

import kernel.devices.console

pack Rect {
	x: u32
	y: u32
	width: u32
	height: u32

	left => x
	top => y
	right => x + width
	bottom => y + height

	shared new(): Rect {
		return pack { x: 0, y: 0, width: 0, height: 0 } as Rect
	}

	shared new(x: u32, y: u32, width: u32, height: u32): Rect {
		return pack { x: x, y: y, width: width, height: height } as Rect
	}
}

plain Terminal {
	cells: Array<Cell>
	width: u32
	height: u32

	init(cells: Array<Cell>, width: u32, height: u32) {
		this.width = width
		this.height = height
		this.cells = cells
	}

	get(x: u32, y: u32): Cell {
		require(x < width and y < height, 'Invalid cell coordinates')
		return cells[y * width + x]
	}
}

plain BitmapDescriptorBlockHeader {
	id: u8
	size: u32

	next => (this as link + sizeof(BitmapDescriptorBlockHeader) + size) as BitmapDescriptorBlockHeader
}

plain BitmapDescriptorCommonBlock {
	inline header: BitmapDescriptorBlockHeader
	line_height: u16
	base: u16
	scale_w: u16
	scale_h: u16
	pages: u16
	bit_field: u8
	alpha_channel: u8
	red_channel: u8
	green_channel: u8
	blue_channel: u8
}

plain BitmapDescriptorCharacter {
	id: u32
	x: u16
	y: u16
	width: u16
	height: u16
	x_offset: i16
	y_offset: i16
	x_advance: i16
	page: u8
	channel: u8

	print(): _ {
		debug.put(`[`) debug.write(x) debug.write(', ') debug.write(y) debug.write(', ') debug.write(width) debug.write(', ') debug.write(height) debug.put(`]`)
	}
}

plain BitmapFont {
	pixels: link
	width: u32
	height: u32
	line_height: u32
	characters: Map<u32, BitmapDescriptorCharacter>

	private load_bitmap_file(bitmap_file: link, bitmap_file_size: u64): _ {
		# Extract the image width, height and pixels (.bmp file)
		pixels_offset: u32 = (bitmap_file + 10).(u32*)[]
		width = (bitmap_file + 18).(u32*)[]
		height = (bitmap_file + 22).(u32*)[]
		bits_per_pixel: u16 = (bitmap_file + 28).(u16*)[]

		# Todo: Validate offsets

		debug.write('Image width: ') debug.write_line(width)
		debug.write('Image height: ') debug.write_line(height)
		debug.write('Image bits per pixel: ') debug.write_line(bits_per_pixel)
		require(bits_per_pixel == 32, 'Image must be 32 bits per pixel')

		# Reorder the pixels in place
		pixels = bitmap_file + pixels_offset

		# Flip the image vertically, because we need to start at the top-left corner
		pixel = pixels

		loop (y = 0, y < height / 2, y++) {
			other = pixels + (height - y - 1) * width * sizeof(u32)
			memory.swap(pixel, other, width * sizeof(u32))
			pixel += width * sizeof(u32)
		}

		# Note: Image is now in BGRA format
	}

	private load_characters(allocator: Allocator, descriptor_file: link, descriptor_file_size: u64): _ {
		require(memory.compare(descriptor_file, 'BMF3', sizeof(u32)) == 0, 'Invalid bitmap font descriptor file')

		# Load the blocks
		info_block = (descriptor_file + sizeof(u32)) as BitmapDescriptorBlockHeader
		common_block = info_block.next as BitmapDescriptorCommonBlock
		pages_block = common_block.header.next
		characters_block = pages_block.next
		character_descriptors = (characters_block as link + sizeof(BitmapDescriptorBlockHeader)) as BitmapDescriptorCharacter
		require(info_block.id == 1 and common_block.header.id == 2 and pages_block.id == 3 and characters_block.id == 4, 'Invalid bitmap font descriptor file')

		# Extract the line height
		line_height = common_block.line_height

		# Compute the number of characters
		character_count = characters_block.size / sizeof(BitmapDescriptorCharacter)
		characters = Map<u32, BitmapDescriptorCharacter>(allocator, character_count) using allocator
		character_descriptor = character_descriptors

		# Extract the characters
		loop (i = 0, i < character_count, i++) {
			characters[character_descriptor.id] = character_descriptor
			character_descriptor += sizeof(BitmapDescriptorCharacter)
		}
	}

	init(allocator: Allocator, bitmap_file: link, bitmap_file_size: u64, descriptor_file: link, descriptor_file_size: u64) {
		load_bitmap_file(bitmap_file, bitmap_file_size)
		load_characters(allocator, descriptor_file, descriptor_file_size)
	}

	get_character(character: u32): BitmapDescriptorCharacter {
		result = none as BitmapDescriptorCharacter

		if characters.contains_key(character) {
			result = characters[character]
		} else {
			result = characters[` `]
			require(result !== none, 'Failed to find the space character')
		}

		return result
	}

	address_of(character: BitmapDescriptorCharacter): link {
		return pixels + (character.y * width + character.x) * sizeof(u32)
	}
}

plain FramebufferConsole {
	shared instance: FramebufferConsole

	private framebuffer: link
	private width: u32
	private height: u32
	private counter: u32 = 0
	bitmap_font: BitmapFont = none as BitmapFont

	init(framebuffer: link, width: u32, height: u32) {
		this.framebuffer = framebuffer
		this.width = width
		this.height = height
	}

	address_of(x: u32, y: u32): link {
		return framebuffer + (y * width + x) * sizeof(u32)
	}

	tick(): _ {
		# Todo: Retrieve the correct framebuffer physical address
		hardware_framebuffer = mapper.map_kernel_region(0xc0000000 as link, width * height * sizeof(u32), MAP_NO_CACHE)
		memory.forward_copy(hardware_framebuffer, framebuffer, width * height * sizeof(u32))
	}

	clear(): _ {
		debug.write_line('Framebuffer console: Clearing')
		memory.zero(framebuffer, width * height * sizeof(u32))
	}

	load_font(uefi_information: UefiInformation): _ {
		bitmap_font_file = mapper.to_kernel_virtual_address(uefi_information.bitmap_font_file)
		bitmap_font_descriptor_file = mapper.to_kernel_virtual_address(uefi_information.bitmap_font_descriptor_file)
		bitmap_font = BitmapFont(HeapAllocator.instance, bitmap_font_file, uefi_information.bitmap_font_file_size, bitmap_font_descriptor_file, uefi_information.bitmap_font_descriptor_file_size) using KernelHeap
	}

	move_area(area: Rect, x: u32, y: u32): _ {
		if (x == area.x and y == area.y) or (area.width == 0 and area.height == 0) return

		framebuffer: link = this.framebuffer

		if y > area.y {
			if x > area.x {
				# Source: Before, Under
				# Copy: Inversed, Top-Right corner
				source = address_of(area.right - 1, area.top)
				destination = address_of(x + area.width - 1, y + area.height)

				loop (iy = 0, iy < area.height, iy++) {
					memory.inverse_copy(destination, source, area.width)
					source += width * 4
					destination += width * 4
				}

			} else {
				# Source: After, Under
				# Copy: Normal, Top-Left corner
				source = address_of(area.left, area.top)
				destination = address_of(x, y)

				loop (iy = 0, iy < area.height, iy++) {
					memory.direct_copy(destination, source, area.width)
					source += width * 4
					destination += width * 4
				}
			}
		} else {
			if x > area.x {
				# Source: Before, Above
				# Copy: Inversed, Bottom-Right corner
				source = address_of(area.right - 1, area.bottom - 1)
				destination = address_of(x + area.width - 1, y + area.height - 1)

				loop (iy = 0, iy < area.height, iy++) {
					memory.inverse_copy(destination, source, area.width)
					source -= width * 4
					destination -= width * 4
				}

			} else {
				# Source: After, Above
				# Copy: Normal, Bottom-Left corner
				source = address_of(area.left, area.bottom - 1)
				destination = address_of(x, y + area.height - 1)

				loop (iy = 0, iy < area.height, iy++) {
					memory.direct_copy(destination, source, area.width)
					source -= width * 4
					destination -= width * 4
				}
			}
		}
	}

	fill(x: u32, y: u32, character: BitmapDescriptorCharacter, cell: Cell): _ {
		debug.write('Framebuffer console: Rendering bitmap character ')
		character.print()
		debug.write(' at ') debug.write(x) debug.write(', ') debug.write_line(y)

		source: link = bitmap_font.address_of(character)
		destination: link = address_of(x, y)
		character_width: u16 = character.width
		character_height: u16 = character.height

		loop (iy = 0, iy < character_height, iy++) {
			memory.copy(destination, source, character_width * sizeof(u32))
			
			destination += width * sizeof(u32)
			source += bitmap_font.width * sizeof(u32)
		}
	}

	# Summary: Computes the current rect of the specified cell in the framebuffer
	get_cell_rect(terminal: Terminal, x: u32, y: u32): Rect {
		character = bitmap_font.get_character(terminal[x, y].value)
		rect = Rect.new(0, y * bitmap_font.line_height + character.y_offset, character.width, character.height)

		x_offset = character.x_offset as i64

		loop (ix = 0, ix < x, ix++) {
			character = bitmap_font.get_character(terminal[ix, y].value)
			x_offset += character.x_offset + character.x_advance
		}

		rect.x = math.max(x_offset, 0)
		return rect
	}

	scroll(lines: u32): _ {
		panic('Todo')
	}

	# Summary: Updates the specified cell by rendering it to the framebuffer
	update(terminal: Terminal, x: u32, y: u32, new: Cell): _ {
		debug.write('Framebuffer console: Updating cell at ') debug.write(x) debug.write(', ') debug.write_line(y)

		new_character = bitmap_font.get_character(new.value)
		character_rect = get_cell_rect(terminal, x, y)

		# We need to move the characters after the cell to the correct positions:

		# Compute the rect that contains all the characters after the current character:
		last_character_rect = get_cell_rect(terminal, terminal.width - 1, y)
		source_rect = Rect.new(character_rect.right, character_rect.top, last_character_rect.right - character_rect.right, character_rect.height)

		# Compute the rect where the characters should be moved to:
		destination_rect = Rect.new(character_rect.left + new_character.width, character_rect.top, source_rect.width, source_rect.height)

		# Move the characters:
		# Todo: Enable and test
		# move_area(source_rect, destination_rect.x, destination_rect.y)

		# Render the new character
		fill(character_rect.left, character_rect.top, new_character, new)
	}
}