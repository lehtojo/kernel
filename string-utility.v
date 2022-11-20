constant STRING_DECIMAL_PRECISION = 15

# Summary: Returns the length of the specified string
export length_of(string: link) {
	length = 0

	loop {
		if string[length] == 0 return length
		length++
	}
}

# Summary: Returns the index of the first occurrence of the specified character in the specified string
export index_of(string: link, character: char) {
	length = length_of(string)

	loop (i = 0, i < length, i++) {
		if string[i] == character return i
	}

	return -1
}

# Summary: Converts the specified number into a string and stores it in the specified buffer
export to_string(number: i64, result: link) {
	position = 0

	if number < 0 {
		loop {
			a = number / 10
			remainder = number - a * 10
			number = a

			result[position] = `0` - remainder
			position++

			if number == 0 stop
		}

		result[position] = `-`
		position++
	}
	else {
		loop {
			a = number / 10
			remainder = number - a * 10
			number = a

			result[position] = `0` + remainder
			position++

			if number == 0 stop
		}
	}

	memory.reverse(result, position)
	return position
}

# Summary: Converts the specified number into a string and stores it in the specified buffer
export to_hexadecimal(value, result: link) {
	position = 0
	number = value as u64

	loop {
		a = number / 16
		remainder = number - a * 16
		number = a

		if remainder >= 10 {
			result[position] = `a` + remainder - 10
		}
		else {
			result[position] = `0` + remainder
		}

		position++

		if number == 0 stop
	}

	memory.reverse(result, position)
	return position
}

# Summary: Converts the specified number into a string and stores it in the specified buffer
export to_string(number: decimal, result: link) {
	position = to_string(number as i64, result)

	# Remove the integer part
	number -= number as i64

	# Ensure the number is a positive number
	if number < 0 { number = -number }

	# Add the decimal point
	result[position] = `,`
	position++

	# If the number is zero, skip the fractional part computation
	if number == 0 {
		result[position] = `0`
		return position + 1
	}

	# Compute the fractional part
	loop (i = 0, i < STRING_DECIMAL_PRECISION and number > 0, i++) {
		number *= 10
		digit = number as i64
		number -= digit

		result[position] = `0` + digit
		position++
	}

	return position
}

# Summary: Converts the specified string into an integer
export to_integer(string: link, length: i64) {
	require(length >= 0, 'String can not be empty when converting to integer')

	result = 0
	index = 0
	sign = 1

	if string[] == `-` {
		sign = -1
		index++
	}

	loop (index < length) {
		digit = (string[index] as i64) - `0`
		result = result * 10 + digit
		index++
	}

	return result * sign
}

# Summary: Converts the specified string to a decimal using the specified separator
export to_decimal(string: link, length: i64, separator: u8) {
	require(length >= 0, 'String can not be empty when converting to integer')

	# Find the index of the separator
	separator_index = -1

	loop (i = 0, i < length, i++) {
		if string[i] == separator {
			separator_index = i
			stop
		}
	}

	# If the separator does not exist, we can treat the string as an integer
	if separator_index < 0 return to_integer(string, length) as decimal

	# Compute the integer value before the separator
	integer_value = to_integer(string, separator_index) as decimal

	# Compute the index of the first digit after the separator where we start
	start = separator_index + 1
	
	# Set the precision to be equal to the number of digits after the separator by default
	precision = length - start

	# Limit the precision
	if precision > STRING_DECIMAL_PRECISION { precision = STRING_DECIMAL_PRECISION }

	# Compute the index of the digit after the last included digit of the fractional part
	end = start + precision

	fraction = 0
	scale = 1

	loop (i = start, i < end, i++) {
		fraction = fraction * 10 + (string[i] - `0`)
		scale *= 10
	}

	if integer_value < 0 return integer_value - fraction / (scale as decimal)
	return integer_value + fraction / (scale as decimal)
}

# Summary: Converts the specified string to a decimal
export to_decimal(string: link, length: i64) {
	return to_decimal(string, length, `.`)
}
