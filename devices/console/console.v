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

CharacterDevice ConsoleDevice {
	private constant DEFAULT_WIDTH = 80
	private constant DEFAULT_HEIGHT = 25

	private cells: Array<Cell>
	private lines: Array<Line>

	private width: u32
	private height: u32
	private position: u32

	private background: u32
	private foreground: u32

	private information: TerminalInformation

	init(allocator: Allocator, major: u32, minor: u32) {
		CharacterDevice(major, minor)
		this.width = DEFAULT_WIDTH
		this.height = DEFAULT_HEIGHT
		initialize_lines(allocator)
		initialize_terminal_information()
	}

	# Summary: Creates lines and their cells with the specified allocator
	private initialize_lines(allocator: Allocator): _ {
		this.cells = Array<Cell>(allocator, width * height) using allocator
		this.lines = Array<Line>(allocator, height) using allocator
	}

	# Summary: Initializes terminal information with default values
	private initialize_terminal_information(): _ {
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
	private next_line(): _ {
		new_position = position + position % width

		# If we will reach the end of cells, move to the start of the cells, because the cell buffer is cyclic
		if new_position == cells.size { new_position = 0 }

		# Update the position
		position = new_position
	}

	# Summary: Moves to the next character
	private next_character(): _ {
		new_position = position + 1

		# If we will reach the end of cells, move to the start of the cells, because the cell buffer is cyclic
		if new_position == cells.size { new_position = 0 }

		# Update the position
		position = new_position
	}

	# Summary: Writes the specified character
	private write_character(character: u8): _ {
		cells[position] = Cell.new(character, background, foreground)

		# Move over the written character
		next_character()

		# If we are at start of a line, no need to do anything
		if position % width == 0 return

		# If a line ending was written, move to the next line
		if character == `\n` next_line()
	}

	override write(description: OpenFileDescription, data: Array<u8>, offset: u64) {
		debug.write_line('Console device: Writing bytes...')

		loop (i = 0, i < data.size, i++) {
			write_character(data[i])	
		}

		return data.size
	}
	
	# Todo: Remove
	test_read: bool

	override read(description: OpenFileDescription, destination: link, offset: u64, size: u64) {
		debug.write_line('Console device: Reading bytes...')

		# Todo: Remove
		if not test_read {
			test_read = true
			memory.copy(destination, 'meme', 4)
			return 4
		}

		return 0
	}

	# Summary: Returns information about this terminal to the specified buffer
	private get_terminal_information(argument: link): i32 {
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

	private set_terminal_process_gid(argument: u32*): i32 {
		debug.write_line('Console device: Set process gid')
		return 0
	}

	private get_terminal_process_gid(argument: u32*): i32 {
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
}