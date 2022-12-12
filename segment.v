constant SEGMENT_CODE = 1
constant SEGMENT_DATA = 2
constant SEGMENT_STACK = 3

pack Segment {
	type: i8
	start: link
	end: link
}