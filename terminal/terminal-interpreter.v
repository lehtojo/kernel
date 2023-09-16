namespace kernel.terminal

constant MAX_COMMAND_SIZE = 256
constant MAX_ARGUMENTS = 4

constant COMMAND_START = `\e`
constant ARGUMENT_SEPARATOR = `;`
constant ARGUMENTS_END = `m`

constant ERROR_NO_DATA = -1
constant ERROR_NOT_COMMAND = -2
constant ERROR_INCOMPLETE = -3
constant ERROR_NOT_SUPPORTED = -4
constant ERROR_CONTINUE = -5
constant ERROR_INVALID_COMMAND = -6
constant ERROR_TOO_MANY = -7

TerminalInterpreter {
	private allocator: Allocator
	private controller: TerminalController
	private inline buffer: Array<u8>
	private buffer_position: u32 = 0
	private buffer_size => buffer_position
	private interpretation_position: u32

	init(allocator: Allocator, controller: TerminalController) {
		this.allocator = allocator
		this.controller = controller
		buffer.init(allocator, MAX_COMMAND_SIZE)
	}

	private is_end(): bool {
		return interpretation_position == buffer_position
	}

	private output_until(position: u32): _ {
		require(position <= buffer_size, 'Terminal interpreter: Invalid buffer position')

		controller.write_raw(buffer, position)
		remove_until(position)
	}

	private remove_until(position: u32): _ {
		require(position <= buffer_size, 'Terminal interpreter: Invalid buffer position')

		data_after_position = buffer_size - position
		memory.copy_into(buffer, 0, buffer, position, data_after_position)

		buffer_position -= position
	}

	private find_next_command(): i64 {
		loop (i = 0, i < buffer_size, i++) {
			if buffer[i] == COMMAND_START return i
		}

		return -1
	}

	private output_until_command(): _ {
		command_start = find_next_command()

		if command_start >= 0 {
			output_until(command_start)
		} else {
			output_until(buffer_size)
		}
	}

	private peek(): u8 {
		if interpretation_position >= buffer_position return 0
		return buffer[interpretation_position]
	}

	private consume(): u8 {
		if interpretation_position >= buffer_position return 0
		return buffer[interpretation_position++]
	}

	private consume(amount: u32): _ {
		interpretation_position = math.min(interpretation_position + amount, buffer_size)
	}

	private consume_integer(max_length: u32): i64 {
		require(max_length >= 1 and not is_end() and is_digit(peek()), 'Terminal interpreter: Failed to consume integer')

		length = 1

		loop (length < max_length, length++) {
			position = interpretation_position + length
			if position == buffer_size or not is_digit(buffer[position]) stop
		}

		integer = to_integer(buffer.data + interpretation_position, length)
		consume(length)
		return integer
	}

	private consume_arguments(arguments: List<String>, max_arguments: u32): i64 {
		if arguments.size >= max_arguments return ERROR_TOO_MANY

		parameter_start = interpretation_position
		parameter_end = parameter_start

		# Update the interpretation position before returning
		deinit { interpretation_position = parameter_end + 1 }

		loop (parameter_end < buffer_size) {
			character = buffer[parameter_end]

			if character == ARGUMENT_SEPARATOR {
				argument = String.new(buffer.data + parameter_start, parameter_end - parameter_start)
				arguments.add(argument)
	
				parameter_start = parameter_end + 1

				# Return an error if we can not consume more arguments, because there are more
				if arguments.size >= max_arguments return ERROR_TOO_MANY

			} else character == ARGUMENTS_END {
				argument = String.new(buffer.data + parameter_start, parameter_end - parameter_start)
				arguments.add(argument)
				return 0
			}

			parameter_end++
		}

		# Arguments are always terminated, but we did not find the terminator character
		return ERROR_INVALID_COMMAND
	}

	private interpret_sgr_sequence(id: u32): i64 {
		return when (id) {
			0 => {
				controller.reset_attributes()
				0
			},
			else => ERROR_NOT_SUPPORTED
		}
	}

	private interpret_color_sequence(id: u32, arguments: List<String>): i64 {
		if as_integer(arguments[0]) has not mode return ERROR_INVALID_COMMAND

		color = 0

		if mode == 5 {
			# Pattern: CSI 48 ; 5 ; <color> m
			if arguments.size != 2 return ERROR_INVALID_COMMAND

			if as_integer(arguments[1]) has not standard_color return ERROR_INVALID_COMMAND

			color = get_256_color(standard_color)

		} else mode == 2 {
			# Pattern: CSI 48 ; 2 ; <r> ; <g> ; <b> m
			if arguments.size != 4 return ERROR_INVALID_COMMAND

			if as_integer(arguments[1]) has not r return ERROR_INVALID_COMMAND
			if as_integer(arguments[2]) has not g return ERROR_INVALID_COMMAND
			if as_integer(arguments[3]) has not b return ERROR_INVALID_COMMAND

			color = r | (g <| 8) | (b <| 16)
		} else {
			return ERROR_NOT_SUPPORTED
		}

		if id == 38 {
			controller.set_foreground_color(color)
		} else id == 48 {
			controller.set_background_color(color)
		} else {
			return ERROR_NOT_SUPPORTED
		}

		return 0
	}

	private interpret_sgr_sequence(id: u32, arguments: List<String>): i64 {
		return when (id) {
			38 => interpret_color_sequence(id, arguments),
			48 => interpret_color_sequence(id, arguments),
			else => ERROR_NOT_SUPPORTED
		}
	}

	private interpret_sgr_sequence(): i64 {
		# CSI = ESC [
		# Pattern: CSI n m/;
		next_character = peek()

		# CSI m = CSI 0 m
		if next_character == ARGUMENTS_END return interpret_sgr_sequence(0)

		# If the next character is not a digit, we do not have a display attribute sequence
		if not is_digit(next_character) return ERROR_CONTINUE

		# Read the command integer 
		command = consume_integer(3)

		# Expect a terminator character (m, ;)
		if is_end() return ERROR_INCOMPLETE

		terminator = consume()

		# Pattern: CSI n m
		if terminator == ARGUMENTS_END {
			return interpret_sgr_sequence(command)
		}

		# Pattern: CSI n ; $argument-1 ; $argument-2 ; ... ; $argument-i m
		if terminator != ARGUMENT_SEPARATOR return ERROR_INVALID_COMMAND

		# Read arguments until the terminator (m)
		argument_allocator = BufferAllocator(buffer: u8[128], 128)
		arguments = List<String>(argument_allocator)

		arguments_result = consume_arguments(arguments, MAX_ARGUMENTS)
		if arguments_result != 0 return arguments_result

		return interpret_sgr_sequence(command, arguments)
	}

	private interpret_csi_sequence(): i64 {
		# CSI = ESC [
		# Pattern: CSI ... 

		# All sequences need something after CSI
		if is_end() return ERROR_INCOMPLETE

		result = interpret_sgr_sequence()
		if result != ERROR_CONTINUE return result

		return ERROR_NOT_SUPPORTED
	}

	private reset_interpretation_state(): _ {
		interpretation_position = 0
	}

	private interpret_command(): i64 {
		if buffer_size == 0 return ERROR_NO_DATA

		reset_interpretation_state()

		# Pattern: ESC ...
		if consume() != COMMAND_START return ERROR_NOT_COMMAND

		# If we do not have anything after the escape code, the command must be incomplete
		if is_end() return ERROR_INCOMPLETE

		# Pattern: ESC [ ...
		if consume() == `[` {
			return interpret_csi_sequence()
		}

		# Pattern: ESC ...

		return ERROR_NOT_SUPPORTED
	}

	interpret(): _ {
		loop {
			output_until_command()

			result = interpret_command()

			if result == 0 {
				# Discard the interpreted command, because it has been executed
				remove_until(interpretation_position)
				continue
			}

			# If there is nothing, we need more data
			if result == ERROR_NO_DATA stop

			# If the command is incomplete, we might need more data
			if result == ERROR_INCOMPLETE {
				# If we have more space in the buffer, try to complete the command by loading more
				if buffer_size < MAX_COMMAND_SIZE stop

				# We have to discard the incomplete command, because it takes up the whole buffer.
				# Most probable reason for this to happen is a corrupted or unsupported command.
				remove_until(buffer_size)
				stop
			}

			# Discard the garbage that we can not make sense of
			remove_until(interpretation_position)
		}
	}

	interpret(data: Array<u8>): _ {
		debug.write_line('Terminal interpreter: Interpreting data...')

		data_position = 0

		loop {
			data_remaining = data.size - data_position
			if data_remaining == 0 stop

			buffer_remaining = buffer.size - buffer_position

			# Compute how much can we copy into the buffer
			transfer_size = math.min(data_remaining, buffer_remaining)

			# Copy the data into the buffer
			memory.copy_into(buffer, buffer_position, data, data_position, transfer_size)
			data_position += transfer_size
			buffer_position += transfer_size

			# Interpret everything in buffer
			interpret()
		}
	}
}