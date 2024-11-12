init() {
	console.write('\e[38;5;10m')
	console.write('\e[48;5;5m')
	console.write_line(' Hello there :^) \e[0m')
	###
	console.write('\e[3')
	loop (i = 0, i < 1000000000, i++) {
		loop (j = 0, j < 10, j++) {}
	}
	console.write('8;5;10m')
	console.write('\e[48;5;5m')
	console.write_line(' Hello there :^) \e[0m')
	###
	return 0
}