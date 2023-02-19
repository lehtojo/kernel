namespace kernel.system_calls

# System call: execve
export system_execve(filename: link, arguments: link, environment_variables: link): i32 {
	debug.write('System call: Execute: ')
	debug.write('filename=') debug.write_address(filename)
	debug.write(', arguments=') debug.write_address(arguments)
	debug.write(', environment_variables=') debug.write_address(environment_variables)
	debug.write_line()

	panic('Todo: Implement')
	return 0
}