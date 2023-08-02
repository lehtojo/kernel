namespace kernel.system_calls

import kernel.time

constant CLOCK_REALTIME = 0

realtime_clock_get_time(timestamp: Timestamp*): u64 {
	time = DateTime()
	result = Time.instance.get_time(time)
	if result != 0 return result

	unix_seconds = time.unix_seconds
	nanoseconds = time.nanosecond

	debug.write('System call: clock_getttime: Unix time: ')
	debug.write(unix_seconds)
	debug.put(`.`)
	debug.write_line(nanoseconds)

	timestamp[].seconds = unix_seconds
	timestamp[].nanoseconds = nanoseconds
	return 0
}

# System call: clock_gettime
export system_clock_getttime(clock: u64, timestamp_argument: u64): u64 {
	debug.write('System call: clock_getttime: ')
	debug.write('clock=') debug.write(clock)
	debug.write(', timestamp=') debug.write_address(timestamp_argument) debug.write_line()

	if clock == CLOCK_REALTIME return realtime_clock_get_time(timestamp_argument as Timestamp*)

	return 0
}