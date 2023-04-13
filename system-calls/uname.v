namespace kernel.system_calls

constant SYSTEM_NAME = 'Linux'
constant NODE_NAME = 'lehtojo'
constant RELEASE = '6.0.0'
constant VERSION = '6.0.0'
constant MACHINE = 'x86_64'

constant FIELD_LENGTH = 65

plain SystemInformation {
	system_name: u8[FIELD_LENGTH]
	node_name: u8[FIELD_LENGTH]
	release: u8[FIELD_LENGTH]
	version: u8[FIELD_LENGTH]
	machine: u8[FIELD_LENGTH]
}

# System call: uname
export system_uname(buffer: link): u64 {
	debug.write('System call: Uname: buffer=')
	debug.write_address(buffer)
	debug.write_line()

	system_name_length = length_of(SYSTEM_NAME)
	node_name_length = length_of(NODE_NAME)
	release_length = length_of(RELEASE)
	version_length = length_of(VERSION)
	machine_length = length_of(MACHINE)

	process = get_process()

	# Verify the specified buffer is large enough
	if not is_valid_region(process, buffer, sizeof(SystemInformation), true) {
		debug.write_line('System call: Uname: Buffer is not large enough')
		return EFAULT
	}

	# Copy the data into userspace
	output = buffer as SystemInformation
	memory.copy(output.system_name, SYSTEM_NAME, system_name_length + 1)
	memory.copy(output.node_name, NODE_NAME, node_name_length + 1)
	memory.copy(output.release, RELEASE, release_length + 1)
	memory.copy(output.version, VERSION, version_length + 1)
	memory.copy(output.machine, MACHINE, machine_length + 1)

	return 0
}