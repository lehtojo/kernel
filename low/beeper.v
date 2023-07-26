namespace kernel.low.Beeper

start_frequency(frequency: u32): _ {
	# Configure the frequency
	divisor = 1193180 / frequency
	ports.write_u8(0x43, 0xb6)
	ports.write_u8(0x42, divisor as u8)
	ports.write_u8(0x42, (divisor |> 8) as u8)

	# Turn on the speaker
	configuration = ports.read_u8(0x61)

	if (configuration & 0b11) != 0b11 {
		ports.write_u8(0x61, configuration | 0b11)
	}
}

stop_frequency(): _ {
	# Turn off the speaker
	configuration = ports.read_u8(0x61)

	ports.write_u8(0x61, configuration & (!0b11))
}

play(frequency: u32): _ {
	start_frequency(frequency)
	wait_for_millisecond()
	stop_frequency()
	wait_for_millisecond()
}