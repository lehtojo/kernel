namespace kernel.time

TimeInterface {
	open get_time(time: DateTime): u64
	open set_time(time: DateTime): u64
}