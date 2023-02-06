pack Range {
	start: u64
	end: u64
	size => end - start

	shared new(start: u64, end: u64): Range {
		return pack { start: start, end: end } as Range
	}

	inside(index: u64): bool { return index >= start and index < end }
	inside(start: u64, size: u64): bool { return start >= this.start and start + size <= end }
	inside(range: Range): bool { return range.start <= range.end and range.start >= start and range.end <= end }

	outside(index: u64): bool { return not inside(index) }
	outside(start: u64, end: u64): bool { return not inside(start, end) }
	outside(range: Range): bool { return not inside(range) }
}