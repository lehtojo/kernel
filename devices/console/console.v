namespace kernel.devices.console

import kernel.system_calls
import kernel.file_systems

pack Cell {
	value: u8
	background: u32
	foreground: u32
	flags: u16

	shared new(value: u8, background: u32, foreground: u32): Cell {
		return pack { value: value, background: background, foreground: foreground, flags: 0 as u16 } as Cell
	}
}

pack Line {
	dirty: bool
}

constant NCCS = 20 

pack TerminalInformation {
	iflag: u16
	oflag: u16
	cflag: u16
	lflag: u16
	ispeed: u32
	ospeed: u32
	characters: u8[NCCS]
}

constant CTRL = 0x1f

constant VINTR = 0
constant VQUIT = 1
constant VERASE = 2
constant VKILL = 3
constant VEOF = 4
constant VTIME = 5
constant VMIN = 6
constant VSWTC = 7
constant VSTART = 8
constant VSTOP = 9
constant VSUSP = 10
constant VEOL = 11
constant VREPRINT = 12
constant VDISCARD = 13
constant VWERASE = 14
constant VLNEXT = 15
constant VEOL2 = 16
constant VINFO = 17

constant ICRNL = 0400
constant OPOST = 0000001
constant ONLCR = 0000004
constant ISIG = 0000001
constant ICANON = 02
constant ECHO = 0000010
constant ECHOE = 0000020
constant ECHOK = 0000040
constant ECHONL = 0000100
constant CS8 = 0000060
constant B9600 = 0000015

# Default values for terminal information
constant TERMINAL_DEFAULT_IFLAG = ICRNL
constant TERMINAL_DEFAULT_OFLAG = OPOST | ONLCR
constant TERMINAL_DEFAULT_LFLAG_NOECHO = ISIG | ICANON
constant TERMINAL_DEFAULT_LFLAG_ECHO = TERMINAL_DEFAULT_LFLAG_NOECHO | ECHO | ECHOE | ECHOK | ECHONL
constant TERMINAL_DEFAULT_LFLAG = TERMINAL_DEFAULT_LFLAG_ECHO
constant TERMINAL_DEFAULT_CFLAG = CS8
constant TERMINAL_DEFAULT_SPEED = B9600

# Control requests
constant TCGETS = 0x5401
constant TIOCSPGRP = 0x5410
constant TIOCGPGRP = 0x540F

pack Rect {
	x: i32
	y: i32
	width: u32
	height: u32

	left => x
	top => y
	right => x + width
	bottom => y + height

	shared new(): Rect {
		return pack { x: 0, y: 0, width: 0, height: 0 } as Rect
	}

	shared new(x: i32, y: i32, width: u32, height: u32): Rect {
		return pack { x: x, y: y, width: width, height: height } as Rect
	}

	shared from_sides(left: i32, top: i32, right: i32, bottom: i32): Rect {
		require(left <= right and top <= bottom, 'Invalid sides')
		return pack { x: left, y: top, width: right - left, height: bottom - top } as Rect
	}

	clamp(rect: Rect): Rect {
		return Rect.from_sides(
			math.clamp(left, rect.left, rect.right),
			math.clamp(top, rect.top, rect.bottom),
			math.clamp(right, rect.left, rect.right),
			math.clamp(bottom, rect.top, rect.bottom)
		)
	}

	print(): _ {
		debug.put(`[`) debug.write(x) debug.write(', ') debug.write(y) debug.write(', ') debug.write(width) debug.write(', ') debug.write(height) debug.put(`]`)
	}
}

plain Viewport {
	width: u32
	height: u32
	line: u32 = 0

	init(width: u32, height: u32) {
		this.width = width
		this.height = height
	}
}

pack Terminal {
	cells: Array<Cell>
	width: u32
	height: u32
	viewport: Viewport

	shared new(cells: Array<Cell>, width: u32, height: u32, viewport: Viewport): Terminal {
		return pack { cells: cells, width: width, height: height, viewport: viewport } as Terminal
	}

	get(x: u32, y: u32): Cell {
		require(x < width and y < height, 'Invalid cell coordinates')
		return cells[y * width + x]
	}
}

pack ConsoleInputBuffer {
	private data: List<u8>
	private capacity: u64

	size => data.size

	shared new(allocator: Allocator, capacity: u64): ConsoleInputBuffer {
		return pack { data: List<u8>(allocator, capacity, false) using allocator, capacity: capacity } as ConsoleInputBuffer
	}

	remove(): _ {
		if data.size == 0 return
		data.remove_at(data.size - 1)
	}

	emit(value: u8): _ {
		# If we are at the least character, allow only line ending
		if value != `\n` and data.size + 1 == capacity return

		data.add(value)
	}

	read(destination: link, size: u64): u64 {		
		read = math.min(data.size, size)
		memory.copy(destination, data.data, read)
		data.remove_all(0, read)
		return read
	}
}

CharacterDevice ConsoleDevice {
	protected constant DEFAULT_WIDTH = 80
	protected constant DEFAULT_HEIGHT = 20
	protected constant DEFAULT_BUFFER_HEIGHT = 100

	protected width: u32
	protected height: u32
	protected cursor: u32
	protected cells: Array<Cell>
	protected lines: Array<Line>
	protected input: ConsoleInputBuffer

	protected viewport: Viewport

	protected background: u32
	protected foreground: u32

	protected information: TerminalInformation

	init(allocator: Allocator, major: u32, minor: u32) {
		CharacterDevice.init(major, minor)
		this.width = DEFAULT_WIDTH
		this.height = DEFAULT_BUFFER_HEIGHT
		this.cursor = 0
		this.viewport = Viewport(DEFAULT_WIDTH, DEFAULT_HEIGHT) using allocator
		initialize_lines(allocator)
		initialize_terminal_information()
	}

	# Summary: Creates lines and their cells with the specified allocator
	protected initialize_lines(allocator: Allocator): _ {
		this.cells = Array<Cell>(allocator, width * height) using allocator
		this.lines = Array<Line>(allocator, height) using allocator
		this.input = ConsoleInputBuffer.new(allocator, PAGE_SIZE * 2)
	}

	# Summary: Initializes terminal information with default values
	protected initialize_terminal_information(): _ {
		information.iflag = TERMINAL_DEFAULT_IFLAG
		information.oflag = TERMINAL_DEFAULT_OFLAG
		information.cflag = TERMINAL_DEFAULT_CFLAG
		information.lflag = TERMINAL_DEFAULT_LFLAG
		information.characters[VINTR] = `c` & CTRL
		information.characters[VQUIT] = 0x1c
		information.characters[VERASE] = 0x08
		information.characters[VKILL] = `u` & CTRL
		information.characters[VEOF] = `d` & CTRL
		information.characters[VTIME] = 0
		information.characters[VMIN] = 1
		information.characters[VSWTC] = 0
		information.characters[VSTART] = `q` & CTRL
		information.characters[VSTOP] = `s` & CTRL
		information.characters[VSUSP] = `z` & CTRL
		information.characters[VEOL] = 0
		information.characters[VREPRINT] = `r` & CTRL
		information.characters[VDISCARD] = `o` & CTRL
		information.characters[VWERASE] = `w` & CTRL
		information.characters[VLNEXT] = `v` & CTRL
		information.characters[VEOL2] = 0
		information.ispeed = TERMINAL_DEFAULT_SPEED
		information.ospeed = TERMINAL_DEFAULT_SPEED
	}

	override get_name() {
		return String.new('tty')
	}

	override can_read(description: OpenFileDescription) { return true }
	override can_write(description: OpenFileDescription) { return true }

	# Summary: Moves to the next line
	protected next_line(): _ {
		new_cursor = (cursor / width + 1) * width

		# If we will reach the end of cells, move to the start of the cells, because the cell buffer is cyclic
		if new_cursor == cells.size { new_cursor = 0 }

		# Update the cursor
		cursor = new_cursor
	}

	# Summary: Moves to the next character
	protected next_character(): _ {
		new_cursor = cursor + 1

		# If we will reach the end of cells, move to the start of the cells, because the cell buffer is cyclic
		if new_cursor == cells.size { new_cursor = 0 }

		# Update the cursor
		cursor = new_cursor
	}

	# Summary: Writes the specified character
	protected write_character_default(character: u8): _ {
		cells[cursor] = Cell.new(character, background, foreground)

		# Move over the written character
		next_character()

		# If we are at start of a line, no need to do anything
		if cursor % width == 0 return

		# If a line ending was written, move to the next line
		if character == `\n` next_line()
	}

	# Summary: Writes the specified character
	open write_character(character: u8): _ {
		write_character_default(character)
	}

	# Summary: Removes the character before the cursor
	protected remove_input_character(): _ {
		if input.size == 0 return

		# Remove the character
		cursor--
		write_character(0)
		cursor--
	}

	override write(description: OpenFileDescription, data: Array<u8>, offset: u64) {
		debug.write_line('Console device: Writing bytes...')

		loop (i = 0, i < data.size, i++) {
			write_character(data[i])	
		}

		description.offset = cursor

		update()
		return data.size
	}

	override read(description: OpenFileDescription, destination: link, offset: u64, size: u64) {
		debug.write_line('Console device: Reading bytes...')
		return input.read(destination, size)
	}

	# Summary: Returns information about this terminal to the specified buffer
	protected get_terminal_information(argument: link): i32 {
		debug.write_line('Console device: Getting information')

		# If the specified output buffer can not receive the information, return error code
		if not is_valid_region(get_process(), argument, sizeof(TerminalInformation), true) return EFAULT

		output = argument as TerminalInformation*
		output[].iflag = information.iflag
		output[].oflag = information.oflag
		output[].cflag = information.cflag
		output[].lflag = information.lflag
		output[].ispeed = information.ispeed
		output[].ospeed = information.ospeed

		loop (i = 0, i < NCCS, i++) {
			output[].characters[i] = information.characters[i]
		}

		return 0
	}

	protected set_terminal_process_gid(argument: u32*): i32 {
		debug.write_line('Console device: Set process gid')
		return 0
	}

	protected get_terminal_process_gid(argument: u32*): i32 {
		debug.write_line('Console device: Get process gid')
		return 0
	}

	override control(request: u32, argument: u64) {
		return when (request) {
			TCGETS => get_terminal_information(argument as link),
			TIOCSPGRP => set_terminal_process_gid(argument as u32*),
			TIOCGPGRP => get_terminal_process_gid(argument as u32*),
			else => {
				debug.write('Console device: Unsupported control request ')
				debug.write_line(request)
				(-1 as i32)
			}
		}
	}

	# Summary: Processes the specified character
	open emit(character: u8): _ {
		debug.write('Console device: Emiting ') debug.write_address(character) debug.write_line()

		input.emit(character)
		write_character(character)
		update()
	}

	scroll_default(lines: i32): _ {
		viewport.line = (viewport.line + lines) % height
	}

	open scroll(lines: i32): _ {
		scroll_default(lines)
		update()
	}

	# Summary: Called when the console content is updated
	open update() {
		subscribers.update()
	}
}