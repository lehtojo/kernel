namespace kernel.time

constant TIME_ZONE_UNSPECIFIED = 0x7ff

constant MINUTE_AS_SECONDS = 60
constant HOUR_AS_SECONDS = 60 * MINUTE_AS_SECONDS
constant DAY_AS_SECONDS = 24 * HOUR_AS_SECONDS
constant YEAR_AS_SECONDS = 365 * DAY_AS_SECONDS
constant LEAP_YEAR_AS_SECONDS = 366 * DAY_AS_SECONDS

plain DateTime {
	shared UNIX_EPOCH: DateTime

	year: u16
	month: u8
	day: u8
	hour: u8
	minute: u8
	second: u8
	padding: u8
	nanosecond: u32
	time_zone: i16
	daylight: u8
	padding_2: u8

	init() {
		this.year = 0
		this.month = 0
		this.day = 0
		this.hour = 0
		this.minute = 0
		this.second = 0
		this.nanosecond = 0
		this.time_zone = 0
		this.daylight = 0
	}

	init(year: u16, month: u8, day: u8, hour: u8, minute: u8, second: u8, nanosecond: u32, time_zone: i16, daylight: u8) {
		this.year = year
		this.month = month
		this.day = day
		this.hour = hour
		this.minute = minute
		this.second = second
		this.nanosecond = nanosecond
		this.time_zone = time_zone
		this.daylight = daylight
	}

	is_leap_year(year: u64): bool {
		return (year % 4 == 0 and year % 100 != 0) or year % 400 == 0
	}

	unix_seconds(): u64 {
		days_in_month: u32[13]
		days_in_month[0] = 0
		days_in_month[1] = 31
		days_in_month[2] = 28
		days_in_month[3] = 31
		days_in_month[4] = 30
		days_in_month[5] = 31
		days_in_month[6] = 30
		days_in_month[7] = 31
		days_in_month[8] = 31
		days_in_month[9] = 30
		days_in_month[10] = 31
		days_in_month[11] = 30
		days_in_month[12] = 31

		total = 0

		# Add years as seconds while taking leap years into account
		loop (y = 1970, y < year, y++) {
			if is_leap_year(y) {
				total += LEAP_YEAR_AS_SECONDS
			} else {
				total += YEAR_AS_SECONDS
			}
		}

		# Add months as seconds
		loop (m = 1, m < month, m++) {
			total += days_in_month[m] * DAY_AS_SECONDS

			if m == 2 and is_leap_year(year) {
				total += DAY_AS_SECONDS # February during a leap year has 29 days
			}
		}

		# Add days as seconds
		total += (day - 1) * DAY_AS_SECONDS

		# Add hours, minutes as seconds
		total += hour * HOUR_AS_SECONDS
		total += minute * MINUTE_AS_SECONDS
		total += second

		return total
	}

	output(): _ {
		debug.write(day) debug.put(`.`) debug.write(month) debug.put(`.`) debug.write(year)
		debug.put(` `) debug.write(hour) debug.put(`:`) debug.write(minute) debug.put(`:`) debug.write(second)
		debug.put(`.`) debug.write(nanosecond)
	}
}