constant REGION_UNKNOWN = -1
constant REGION_AVAILABLE = 1
constant REGION_RESERVED = 2

constant SEGMENT_CODE = 1
constant SEGMENT_DATA = 2
constant SEGMENT_STACK = 3

pack Segment {
	type: i8
	start: link
	end: link
	size => (end - start) as u64

	shared new(type: i8): Segment {
		return pack { type: type, start: 0, end: 0 } as Segment
	}

	shared new(type: i8, start: link, end: link): Segment {
		return pack { type: type, start: start, end: end } as Segment
	}

	shared new(start: link, end: link): Segment {
		return pack { type: 0, start: start, end: end } as Segment
	}
}