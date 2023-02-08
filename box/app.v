import 'C' system_open(path: link, flags: i64, mode: i64): i64
import 'C' system_seek(file_descriptor: i64, offset: u64, whence: u32): i64
import 'C' system_read(file_descriptor: i64, buffer: link, size: u64): i64
import 'C' system_write(file_descriptor: i64, buffer: link, size: i64): i64
import 'C' system_close(file_descriptor: i64): i64

constant O_CREAT = 0x40
constant O_RDONLY = 0
constant O_WRONLY = 1

constant SEEK_SET = 0
constant SEEK_CUR = 1
constant SEEK_END = 2

export test_1() {
	source_file_descriptor = system_open('/home/user/lorem.txt', O_RDONLY, 777)
	if source_file_descriptor < 0 return console.write_line('Failed to open lorem.txt')

	source_file_size = system_seek(source_file_descriptor, 0, SEEK_END)
	source_data = Array<u8>(source_file_size)

	system_seek(source_file_descriptor, 0, SEEK_SET)
	
	if system_read(source_file_descriptor, source_data.data, source_file_size) != source_file_size {
		console.write_line('Failed to read lorem.txt')
		system_close(source_file_descriptor)
		return
	}

	system_close(source_file_descriptor)

	console.write_line(String(source_data.data, source_file_size))

	destination_file_descriptor = system_open('/home/user/test.txt', O_CREAT | O_WRONLY, 777)
	if destination_file_descriptor < 0 return console.write_line('Failed to open test.txt')

	test_data = "Hello there :^)"
	written = system_write(destination_file_descriptor, test_data.data, test_data.length)

	console.write_line("Wrote " + to_string(written) + ' bytes into test.txt')

	system_close(destination_file_descriptor)
}

init() {
	console.write_line("Starting...")
	test_1()
	console.write_line("Exiting...")
	return 0
}