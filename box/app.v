import 'C' system_open(path: link, flags: i64, mode: i64): i64
import 'C' system_write(file_descriptor: i64, buffer: link, size: i64): i64
import 'C' system_close(file_descriptor: i64): i64

constant O_CREAT = 0x40

export test_1() {
	file_descriptor = system_open('/home/user/test.txt', O_CREAT | 1, 777)
	if file_descriptor < 0 return console.write_line('Failed to open test.txt')

	test_data = "Hello there :^)"
	written = system_write(file_descriptor, test_data.data, test_data.length)

	console.write_line("Wrote " + to_string(written) + ' bytes into test.txt')

	system_close(file_descriptor)
}

init() {
	console.write_line("Starting...")
	test_1()
	console.write_line("Exiting...")
	return 0
}