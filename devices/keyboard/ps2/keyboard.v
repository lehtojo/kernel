namespace kernel.devices.keyboard.ps2.keyboard

import kernel.devices
import kernel.devices.console

constant KEYCODE_COUNT = 128

constant LEFT_SHIFT = 0x2a
constant RIGHT_SHIFT = 0x36

layout: u8*
shift_layout: u8*
states: u8*

export initialize(allocator: Allocator) {
	layout = allocator.allocate(KEYCODE_COUNT * 2)
	shift_layout = allocator.allocate(KEYCODE_COUNT * 2)
	states = layout + KEYCODE_COUNT

	memory.zero(layout, KEYCODE_COUNT)
	memory.zero(shift_layout, KEYCODE_COUNT)
	memory.zero(states, KEYCODE_COUNT)

	# Keycode layout:
	layout[2] = `1`
	layout[3] = `2`
	layout[4] = `3`
	layout[5] = `4`
	layout[6] = `5`
	layout[7] = `6`
	layout[8] = `7`
	layout[9] = `8`
	layout[10] = `9`
	layout[11] = `0`
	layout[12] = `-`
	layout[13] = `=`

	layout[16] = `q`
	layout[17] = `w`
	layout[18] = `e`
	layout[19] = `r`
	layout[20] = `t`
	layout[21] = `y`
	layout[22] = `u`
	layout[23] = `i`
	layout[24] = `o`
	layout[25] = `p`
	layout[26] = `[`
	layout[27] = `]`
	layout[28] = `\n`

	layout[30] = `a`
	layout[31] = `s`
	layout[32] = `d`
	layout[33] = `f`
	layout[34] = `g`
	layout[35] = `h`
	layout[36] = `j`
	layout[37] = `k`
	layout[38] = `l`
	layout[39] = `;`

	# layout[41] = `\``

	layout[44] = `z`
	layout[45] = `x`
	layout[46] = `c`
	layout[47] = `v`
	layout[48] = `b`
	layout[49] = `n`
	layout[50] = `m`
	layout[51] = `,`
	layout[52] = `.`
	layout[53] = `/`

	layout[57] = ` `

	# Shifted keycode layout:
	shift_layout[2] = `!`
	shift_layout[3] = `@`
	shift_layout[4] = `#`
	shift_layout[5] = `$`
	shift_layout[6] = `%`
	shift_layout[7] = `^`
	shift_layout[8] = `&`
	shift_layout[9] = `*`
	shift_layout[10] = `(`
	shift_layout[11] = `)`
	shift_layout[12] = `_`
	shift_layout[13] = `+`

	# Do not map alphabet as they are handled in code

	shift_layout[51] = `<`
	shift_layout[52] = `>`
	shift_layout[53] = `?`
}

is_alphabet(character: u8): bool {
	return character >= `a` and character <= `z`
}

resolve_keycode(scancode: u8, keycode: u8, is_shift_down: bool): u8 {
	if is_alphabet(keycode) {
		if is_shift_down return keycode - `a` + `A`

		return keycode
	}

	if is_shift_down {
		shifted_keycode = shift_layout[scancode]
		if shifted_keycode != 0 return shifted_keycode
	}

	return keycode
}

export process() {
	scancode = ports.read_u8(0x60)
	down = (scancode & 0x80) == 0
	scancode &= 0x7f # Remove the last bit

	debug.write('Keyboard: Received ') debug.write_address(scancode) debug.write_line()

	keycode = layout[scancode]

	state = states[scancode]
	states[scancode] = down

	is_shift_down = states[LEFT_SHIFT] or states[RIGHT_SHIFT]
	keycode = resolve_keycode(scancode, keycode, is_shift_down)

	if keycode !== 0 and not state {
		require(Devices.instance.find(BootConsoleDevice.MAJOR, BootConsoleDevice.MINOR) has boot_console, 'Missing boot console device')
		boot_console.(ConsoleDevice).emit(keycode)
	}
}