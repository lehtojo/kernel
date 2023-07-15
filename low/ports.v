namespace kernel.ports

namespace internal {
	import 'C' ports_read_u8(port: u8): u8
	import 'C' ports_read_u16(port: u8): u16
	import 'C' ports_read_u32(port: u8): u32

	import 'C' ports_write_u8(port: u8, value: u8)
	import 'C' ports_write_u16(port: u8, value: u16)
	import 'C' ports_write_u32(port: u8, value: u64)
}

read_u8(port: u8): u8 {
	return internal.ports_read_u8(port)
}

read_u16(port: u8): u16 {
	return internal.ports_read_u16(port)
}

read_u32(port: u8): u32 {
	return internal.ports_read_u32(port)
}

write_u8(port: u8, value: u8) {
	internal.ports_write_u8(port, value)
}

write_u16(port: u8, value: u16) {
	internal.ports_write_u16(port, value)
}

write_u32(port: u8, value: u32) {
	internal.ports_write_u32(port, value)
}