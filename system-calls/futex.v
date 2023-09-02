namespace kernel.system_calls

# System call: futex
export system_futex(
	userspace_address_1: u32*,
	operation: i32,
	value_1: u32,
	value_2: u64,
	userspace_address_2: u32*,
	value_3: u32
): u64 {
	debug.write('System call: futex: ')
	debug.write('userspace_address_1=') debug.write_address(userspace_address_1)
	debug.write(', operation=') debug.write(operation)
	debug.write(', value_1=') debug.write(value_1)
	debug.write(', value_2=') debug.write(value_2)
	debug.write(', userspace_address_2=') debug.write_address(userspace_address_2)
	debug.write(', value_3=') debug.write(value_3)
	debug.write_line()	

	# Todo: Implement
	return 0
}