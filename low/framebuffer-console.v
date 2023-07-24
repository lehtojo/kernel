namespace kernel.low

import kernel.devices.console
import kernel.devices.gpu

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
	private framebuffer_width: u32
	private framebuffer_height: u32
	private width: u32
	private height: u32
	private counter: u32 = 0
	private terminal: Terminal
	bitmap_font: BitmapFont = none as BitmapFont
	enabled: bool = true

	init(framebuffer: link, framebuffer_width: u32, framebuffer_height: u32) {
		this.framebuffer = framebuffer
		this.framebuffer_width = framebuffer_width
		this.framebuffer_height = framebuffer_height
		this.width = 0
		this.height = 0
	}

	address_of(x: u32, y: u32): link {
		require(x < width and y < height, 'Pixel coordinates out of bounds')
		return framebuffer + (y * framebuffer_width + x) * sizeof(u32)
	}

	tick(): _ {
		if not enabled return

		if DisplayConnectors.current === none {
			debug.write_line('Framebuffer console: No display connector found')
			return
		}

		framebuffer_size = framebuffer_width * framebuffer_height * sizeof(u32)
		hardware_framebuffer = mapper.map_kernel_region(DisplayConnectors.current.framebuffer, framebuffer_size, MAP_NO_CACHE)
		memory.forward_copy(hardware_framebuffer, framebuffer, framebuffer_size)
	}

	clear(): _ {
		debug.write_line('Framebuffer console: Clearing')
		memory.zero(framebuffer, framebuffer_width * framebuffer_height * sizeof(u32))
	}

	clear(rect: Rect): _ {
		debug.write_line('Framebuffer console: Clearing a region')
		require(rect.left >= 0 and rect.top >= 0 and rect.right <= width and rect.bottom <= height, 'Region is out of bounds')

		# Return if we have nothing to do
		if rect.width == 0 or rect.height == 0 return

		destination = address_of(rect.x, rect.y)

		loop (iy = 0, iy < rect.height, iy++) {
			memory.zero(destination, rect.width * sizeof(u32))
			destination += framebuffer_width * sizeof(u32)
		}
	}

	clear_line(y: u32): _ {
		# Compute the rect that contains the specified line
		line_rect = Rect.new(0, y * line_height, width, line_height)

		# Clamp the rect inside viewport
		viewport_rect = Rect.new(0, terminal.viewport.line * line_height, width, height)
		clamped_rect = line_rect.clamp(viewport_rect)

		clamped_rect.x -= viewport_rect.x
		clamped_rect.y -= viewport_rect.y

		# Clear the line
		clear(clamped_rect)
	}

	set_terminal(terminal: Terminal): _ {
		debug.write_line('Framebuffer console: Setting terminal...')

		this.terminal = terminal

		if terminal.width == 0 or terminal.height == 0 or terminal.cells === none or terminal.viewport === none {
			debug.write_line('Framebuffer console: Terminal is incomplete, not initializing')
			return
		}

		this.width = framebuffer_width
		this.height = terminal.viewport.height * line_height

		debug.write('Framebuffer console: Terminal width: ') debug.write_line(this.width)
		debug.write('Framebuffer console: Terminal height: ') debug.write_line(this.height)
		
		require(this.height <= framebuffer_height, 'Terminal pixel height exceeds framebuffer height')

		clear()
		render_all_lines()
	}

	line_height(): u32 {
		if bitmap_font === none return 0
		return bitmap_font.line_height
	}

	load_font(uefi_information: UefiInformation): _ {
		bitmap_font_file = mapper.to_kernel_virtual_address(uefi_information.bitmap_font_file)
		bitmap_font_descriptor_file = mapper.to_kernel_virtual_address(uefi_information.bitmap_font_descriptor_file)
		bitmap_font = BitmapFont(HeapAllocator.instance, bitmap_font_file, uefi_information.bitmap_font_file_size, bitmap_font_descriptor_file, uefi_information.bitmap_font_descriptor_file_size) using KernelHeap
		set_terminal(terminal)
	}

	move_area(area: Rect, x: u32, y: u32): _ {
		if (x == area.x and y == area.y) or (area.width == 0 and area.height == 0) return

		destination_rect = Rect.new(x, y, area.width, area.height)
		require(destination_rect.left >= 0 and destination_rect.top >= 0 and destination_rect.right <= width and destination_rect.bottom <= height, 'Region is out of bounds')

		framebuffer: link = this.framebuffer

		if y < area.y {
			if x > area.x {
				# Source: Before, Under
				# Copy: Inversed, Top-Right corner
				source = address_of(area.right - 1, area.top)
				destination = address_of(x + area.width - 1, y + area.height)

				loop (iy = 0, iy < area.height, iy++) {
					memory.reverse_copy(destination, source, area.width * sizeof(u32))
					source += width * 4
					destination += width * 4
				}

			} else {
				# Source: After, Under
				# Copy: Normal, Top-Left corner
				source = address_of(area.left, area.top)
				destination = address_of(x, y)

				loop (iy = 0, iy < area.height, iy++) {
					memory.forward_copy(destination, source, area.width * sizeof(u32))
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
					memory.reverse_copy(destination, source, area.width * sizeof(u32))
					source -= width * 4
					destination -= width * 4
				}

			} else {
				# Source: After, Above
				# Copy: Normal, Bottom-Left corner
				source = address_of(area.left, area.bottom - 1)
				destination = address_of(x, y + area.height - 1)

				loop (iy = 0, iy < area.height, iy++) {
					memory.forward_copy(destination, source, area.width * sizeof(u32))
					source -= width * 4
					destination -= width * 4
				}
			}
		}
	}

	fill(rect: Rect, character: BitmapDescriptorCharacter, cell: Cell): _ {
		debug.write('Framebuffer console: Rendering bitmap character ')
		character.print() debug.write(' at ') rect.print() debug.write_line()

		require(rect.left >= 0 and rect.top >= 0 and rect.right <= width and rect.bottom <= height, 'Region is out of bounds')

		# Return if we have nothing to do
		if rect.width == 0 or rect.height == 0 return

		source: link = bitmap_font.address_of(character)
		destination: link = address_of(rect.x, rect.y)

		loop (iy = 0, iy < rect.height, iy++) {
			memory.copy(destination, source, rect.width * sizeof(u32))
			
			destination += framebuffer_width * sizeof(u32)
			source += bitmap_font.width * sizeof(u32)
		}
	}

	# Summary: Computes the rect in which the specified character should be rendered without taking the viewport into account
	absolute_rect(x: u32, y: u32, character: BitmapDescriptorCharacter): Rect {
		require(x < terminal.width and y < terminal.height, 'Invalid cell coordinates')

		rect = Rect.new(0, y * line_height + character.y_offset, character.width, character.height)

		x_offset = character.x_offset as i64

		loop (ix = 0, ix < x, ix++) {
			character = bitmap_font.get_character(terminal[ix, y].value)
			x_offset += character.x_offset + character.x_advance
		}

		rect.x = math.max(x_offset, 0)
		return rect
	}

	# Summary: Computes the rect in which the specified character should be rendered
	viewport_rect(x: u32, y: u32, character: BitmapDescriptorCharacter): Rect {
		rect = absolute_rect(x, y, character)

		viewport_rect = Rect.new(0, terminal.viewport.line * line_height, width, height)
		clamped_rect = rect.clamp(viewport_rect)

		clamped_rect.x -= viewport_rect.x
		clamped_rect.y -= viewport_rect.y
		return clamped_rect
	}

	# Summary: Renders the specified line
	render_line(y: u32): _ {
		debug.write('Framebuffer console: Rendering line ') debug.write_line(y)

		# Clear the line
		clear_line(y)

		# Render the line
		loop (x = 0, x < terminal.width, x++) {
			character = bitmap_font.get_character(terminal[x, y].value)
			rect = viewport_rect(x, y, character)
			fill(rect, character, terminal[x, y])
		}
	}

	# Summary: Render all lines
	render_all_lines(): _ {
		debug.write_line('Framebuffer console: Rendering viewport')

		# Render the lines
		loop (y = 0, y < terminal.height, y++) {
			render_line(y)
		}
	}

	scroll(lines: u32): _ {
		debug.write('Framebuffer console: Scrolling ') debug.write_line(lines)

		# If we scroll more than "one viewport", we can just render everything
		if math.abs(lines) >= terminal.viewport.height {
			render_all_lines()
			return
		}

		# Compute the destination rect:
		destination_rect = Rect.new(0, 0, width, height)

		# Apply the movement to the viewport rect
		destination_rect.y -= lines * line_height

		# Clamp the viewport rect to the framebuffer
		destination_rect = destination_rect.clamp(Rect.new(0, 0, width, height))

		# Compute the source rect:
		# Apply the movement in reverse to the destination rect
		source_rect = destination_rect
		source_rect.y += lines * line_height

		# Move the source rect to the destination rect
		move_area(source_rect, destination_rect.x, destination_rect.y)

		first_new_line = 0

		if lines >= 0 {
			# We are scrolling down:

			# Render the lines at the bottom that became visible
			first_new_line = terminal.viewport.line + terminal.viewport.height - lines

		} else {
			# We are scrolling up:

			# Render the lines at the top that became visible
			first_new_line = terminal.viewport.line
		}

		# Render the new lines that became visible
		loop (y = 0, y < math.abs(lines), y++) {
			render_line(first_new_line + y)
		}
	}

	# Summary: Updates the specified cell by rendering it to the framebuffer
	update(x: u32, y: u32, new: Cell): _ {
		debug.write('Framebuffer console: Updating cell at ') debug.write(x) debug.write(', ') debug.write_line(y)

		# Remove the old character from the framebuffer
		old_character = bitmap_font.get_character(terminal[x, y].value)
		character_rect = viewport_rect(x, y, old_character)
		clear(character_rect)

		# Compute the rect for the new character
		new_character = bitmap_font.get_character(new.value)
		character_rect = viewport_rect(x, y, new_character)

		# Render the new character
		fill(character_rect, new_character, new)
	}
}