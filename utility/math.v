namespace math

min(a, b) {
	if a <= b return a
	return b
}

max(a, b) {
	if a >= b return a
	return b
}

sign_extend_32(value): i64 {
	return (value as i64) <| 32 |> 32
}