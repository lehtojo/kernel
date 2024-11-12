namespace math

abs(a) {
	if a < 0 return -a
	return a
}

min(a, b) {
	if a <= b return a
	return b
}

max(a, b) {
	if a >= b return a
	return b
}

clamp(value, min, max) {
	if value < min return min
	if value > max return max
	return value
}

sign_extend_32(value): i64 {
	return (value as i64) <| 32 |> 32
}