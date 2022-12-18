namespace kernel.keyboard

constant KEYCODE_COUNT = 128

layout: u8*
states: u8*

export initialize(allocator: Allocator) {
	layout = allocator.allocate(KEYCODE_COUNT * 2)
	states = layout + KEYCODE_COUNT

	memory.zero(layout, KEYCODE_COUNT)
	memory.zero(states, KEYCODE_COUNT)

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
}

export process() {
	scancode = ports.read_u8(0x60)
	down = (scancode & 0x80) == 0
	scancode &= 0x7f # Remove the last bit

	keycode = layout[scancode]

	state = states[scancode]
	states[scancode] = down

	if keycode !== 0 and not state {
		debug.put(keycode)
	}
}