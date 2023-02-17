init() {
	console.write('Arguments: ')
	console.write_line(String.join(", ", io.internal.arguments))

	console.write('Environment arguments: ')
	console.write_line(String.join(", ", io.internal.environment_variables))

	return 0
}