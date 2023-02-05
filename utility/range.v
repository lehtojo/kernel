pack Range {
	start: u64
	end: u64
	size => end - start

	shared new(start: u64, end: u64): Range {
		return pack { start: start, end: end } as Range
	}

	inside(i: u64): bool { return i >= start and i < end }
	inside(start: u64, size: u64): bool { return start >= this.start and start + size < end }
	inside(range: Range): bool { return range.start <= range.end and range.start >= start and range.end < end }

	outside(i: u64): bool { return not inside(i) }
	outside(start: u64, end: u64): bool { return not inside(start, end) }
	outside(range: Range): bool { return not inside(range) }
}