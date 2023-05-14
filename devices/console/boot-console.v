namespace kernel.devices.console

ConsoleDevice BootConsoleDevice {
	constant MAJOR = 42
	constant MINOR = 42

	protected framebuffer: link

	init(allocator: Allocator) {
		ConsoleDevice.init(allocator, MAJOR, MINOR)
		this.framebuffer = kernel.mapper.map_kernel_page(0xb8000 as link)
		clear()
	}

	# Summary: Clears the viewport
	protected clear() {
		loop (i = 0, i < viewport.width * viewport.height, i++) {
			framebuffer.(u16*)[i] = 0x0020 # Clear with black spaces
		}

		# Todo: Consider the cursor
	}

	# Summary: Renders the specified viewport line
	protected render_viewport_line(line_offset: u32): _ {
		require(line_offset < viewport.height, 'Too large viewport line offset')

		# Compute the "global" line number by offsetting the "global" viewport line.
		# Also take into account that the line might go past the last line, so it needs to cycle back.
		line = (viewport.line + line_offset) % height

		# Compute the starting address of the framebuffer line
		framebuffer_line = framebuffer + line_offset  * 2 * viewport.width

		loop (i = 0, i < viewport.width, i++) {
			character = cells[line * viewport.width + i].value
			if character == `\n` { character = ` ` }

			framebuffer_line[i * 2] = character
			framebuffer_line[i * 2 + 1] = 0b00000111 # Light gray
		}
	}

	# Summary: Renders all viewport lines
	protected render_viewport(): _ {
		loop (i = 0, i < viewport.height, i++) {
			render_viewport_line(i)
		}
	}

	# Summary: Processes the specified character
	override emit(character: u8) {
		debug.write('Boot console: Emiting ') debug.write_address(character) debug.write_line()

		input.emit(character)
		write_character(character)
		render_viewport()

		if character == `\n` { update() }
	}

	# Summary: Called when the console content is updated
	override update() {
		render_viewport()
		subscribers.update()
	}
}