constant REGION_UNKNOWN = -1
constant REGION_AVAILABLE = 1
constant REGION_RESERVED = 2

constant SEGMENT_CODE = 1
constant SEGMENT_DATA = 2
constant SEGMENT_STACK = 3

# Summary: Represents regions that remain after subtracting a segment from another
pack SegmentSubtraction {
	left: Segment
	right: Segment

	# Summary: Returns a new substraction with empty segments
	shared empty(): SegmentSubtraction {
		return pack { left: Segment.empty, right: Segment.empty } as SegmentSubtraction
	}

	# Summary: Returns a new subtraction with the specified segments
	shared new(left: Segment, right: Segment): SegmentSubtraction {
		return pack { left: left, right: right } as SegmentSubtraction
	}
}

pack Segment {
	type: u64
	start: link
	end: link
	size => (end - start) as u64

	shared empty(): Segment { return pack { type: 0, start: 0, end: 0 } as Segment }

	shared new(type: i8): Segment { return pack { type: type, start: 0, end: 0 } as Segment }
	shared new(type: i8, start, end): Segment { return pack { type: type, start: start as link, end: end as link } as Segment }
	shared new(start, end): Segment { return pack { type: 0, start: start as link, end: end as link } as Segment }

	# Summary: Returns whether this segment contains the specified address
	contains(address: link): bool {
		return address >= start and address < end
	}

	# Summary: Returns whether this segment contains the specified segment
	contains(segment: Segment): bool {
		return segment.start <= segment.end segment.start >= start and segment.end <= end
	}

	# Summary: Returns the intersection between this and the other segment
	intersection(segment: Segment): Segment {
		intersection_start = math.max(start, segment.start)
		intersection_end = math.min(end, segment.end)
		if intersection_start >= intersection_end return Segment.empty

		return Segment.new(segment.type, intersection_start, intersection_end)
	}

	# Summary: Returns whether this segment intersects with the specified segment
	intersects(segment: Segment): bool {
		return intersection(segment).size > 0
	}

	# Summary:
	# Subtracts the other segment from this segment.
	# In other words, the remaining regions are returned.
	subtract(other: Segment): SegmentSubtraction {
		if other.start <= start {
			# Case:
			# +-----------------+
			# |               +-|------------+
			# |     Other     | |   This     |
			# |               +-|------------+
			# +-----------------+			
			if other.end >= end return SegmentSubtraction.empty()
			if other.end <= start return SegmentSubtraction.empty()
			return SegmentSubtraction.new(Segment.empty(), Segment.new(type, other.end, end))
		}

		if other.end >= end {
			# Case:
			#             +----------------+
			# +-----------|-+              |
			# |    This   | |    Other     |
			# +-----------|-+              |
			#             +----------------+
			if other.start <= start return SegmentSubtraction.empty()
			if other.start <= end return SegmentSubtraction.new(Segment.new(type, start, other.start), Segment.empty())
			return SegmentSubtraction.new(Segment.new(type, start, end), Segment.empty())
		}

		# Case:
		# +---+--------------------+---+
		# |   |                    |   |
		# |   |       Other        |   |
		# |   |                    |   |
		# +---+--------------------+---+
		return SegmentSubtraction.new(Segment.new(type, start, other.start), Segment.new(type, other.end, end))
	}

	# Summary: Prints this segment
	print() {
		debug.write_address(start)
		debug.put(`-`)
		debug.write_address(end)
	}
}