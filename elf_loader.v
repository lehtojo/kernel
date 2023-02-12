namespace kernel.elf.loader

import kernel.scheduler

plain LoadInformation {
	allocations: List<MemoryMapping>
	entry_point: u64
}

# TODO: Could integer overflows be exploited?

access<T>(memory: Array<u8>, offset: u64): Optional<T> {
	# If the data structure T starting from the specified offset, goes out of bounds return empty optional
	if memory.size - offset < sizeof(T) return Optionals.empty<T>()
	return Optionals.new<T>((memory.data + offset) as T)
}

is_accessible_region(memory: Array<u8>, offset: u64, bytes: u64): bool {
	return memory.size - offset >= bytes
}

load_program_headers(file: Array<u8>, program_header_table: link, program_header_count: u16, program_headers: Array<ProgramHeader>): bool {
	debug.write('Loader: Processing ')
	debug.write(program_header_count)
	debug.write_line(' program header(s)...')

	# Add all the program headers to the output list
	loop (i = 0, i < program_header_count, i++) {
		program_header = (file.data + program_header_table + i * sizeof(ProgramHeader)) as ProgramHeader

		# TODO: Verify virtual region and alignment
		debug.write('Loader: Program header: Physical address = ')
		debug.write_address(program_header.offset)
		debug.write(', Physical size = ')
		debug.write(program_header.segment_file_size)
		debug.write(', Memory size = ')
		debug.write_line(program_header.segment_memory_size)

		# Verify the loaded file section exists
		if not is_accessible_region(file, program_header.offset, program_header.segment_file_size) {
			debug.write_line('Loader: Invalid program header')
			return false
		}

		program_headers[i] = program_header
	}

	return true
}

export load_executable(file: Array<u8>, output: LoadInformation): bool {
	debug.write('Loader: Loading executable from file at address ')
	debug.write_address(file.data as u64)
	debug.write_line()

	# Access the file header
	if access<FileHeader>(file, 0) has not header {
		debug.write_line('Loader: Failed to access the file header')
		return false
	}

	# Verify the specified file is a ELF-file and that we support it
	if header.magic_number != ELF_MAGIC_NUMBER or 
		header.class != ELF_CLASS_64_BIT or 
		header.endianness != ELF_LITTLE_ENDIAN or 
		header.machine != ELF_MACHINE_TYPE_X64 {
		debug.write_line('Loader: Unsupported executable')
		return false
	}

	# Verify the specified file uses the same data structure for program headers
	if header.program_header_size != sizeof(ProgramHeader) {
		debug.write_line('Loader: Unsupported program headers')
		return false
	}

	# Verify the program headers exist
	program_header_table = header.program_header_offset
	program_header_count = header.program_header_entry_count

	if not is_accessible_region(file, program_header_table, program_header_count * sizeof(ProgramHeader)) {
		debug.write_line('Loader: Failed to access the program headers')
		return false
	}

	# Load the program headers
	program_headers_buffer = KernelHeap.allocate<ProgramHeader>(program_header_count)
	if program_headers_buffer === none return false

	program_headers = Array<ProgramHeader>(program_headers_buffer, program_header_count)

	if not load_program_headers(file, program_header_table as link, program_header_count, program_headers) {
		KernelHeap.deallocate(program_headers_buffer)
		return false
	}

	failed = false

	# Load each segment into memory
	loop (i = 0, i < program_header_count, i++) {
		program_header = program_headers[i]
		segment_data = file.data + program_header.offset
		segment_physical_size = math.min(program_header.segment_file_size, program_header.segment_memory_size)
		segment_virtual_size = memory.round_to_page(
			math.max(program_header.segment_file_size, program_header.segment_memory_size)
		)

		# Load the virtual address from the perspective of the program
		program_segment_virtual_address = program_header.virtual_address

		segment_physical_address = PhysicalMemoryManager.instance.allocate_physical_region(segment_physical_size)
		segment_virtual_address = mapper.map_kernel_region(segment_physical_address, segment_virtual_size)

		# Todo: Deallocate upon failure

		if segment_physical_address === none {
			debug.write_line('Loader: Failed to allocate memory for a loadable segment')
			failed = true
			stop
		}

		# Todo:
		# It seems that the runtime linker has unaligned virtual addresses so take them into consideration.
		# Those addresses crash the kernel.

		debug.write('Loader: Copying ')
		debug.write(segment_physical_size)
		debug.write(' byte(s) from the executable starting at offset ')
		debug.write_address(program_header.offset)
		debug.write(' into virtual address ')
		debug.write_address(program_segment_virtual_address)
		debug.write(' using physical address ')
		debug.write_address(segment_physical_address)
		debug.write_line()

		# Copy the segment data from the file to the allocated segment
		memory.copy(segment_virtual_address, segment_data, segment_physical_size)

		# Add the memory mapping
		output.allocations.add(MemoryMapping.new(
			program_segment_virtual_address as u64,
			segment_physical_address as u64,
			segment_virtual_size
		))
	}

	# Because the program headers were processed, they are no longer needed
	KernelHeap.deallocate(program_headers_buffer)

	if failed {
		return false
	}

	# Register the entry point
	# TODO: Verify the entry point is inside an executable region
	output.entry_point = header.entry
	return true
}

export load_stack_startup_data(physical_stack_address_top: link, arguments: List<String>, environment_variables: List<String>): link {
	# Todo: If there are a lot of arguments and environment variables, stack can overflow

	# Compute the number of bytes needed for the startup data:
	# 0                  8 (bytes)
	# +------------------+
	# |       ...        |
	# |   Environment    |
	# |    variables     |
	# |       ...        |
	# +------------------+
	# |       ...        |
	# |    Arguments     |
	# |       ...        |
	# +------------------+
	# |        0         |
	# +------------------+ 
	# |       ...        |
	# |   Environment    |
	# |     variable     |
	# |     pointers     |
	# |       ...        |
	# +------------------+ 
	# |        0         |
	# +------------------+
	# |       ...        |
	# |     Argument     |
	# |     pointers     |
	# |       ...        |
	# +------------------+
	# |  Argument count  |
	# +------------------+ <--- rsp

	# Compute the number of bytes required for the first two sections
	environment_variable_data_section_size = 0
	argument_data_section_size = 0
	loop (i = 0, i < environment_variables.size, i++) { environment_variable_data_section_size += environment_variables[i].length + 1 }
	loop (i = 0, i < arguments.size, i++) { argument_data_section_size += arguments[i].length + 1 }

	# Ensure the sections sizes are multiple of 8 bytes
	environment_variable_data_section_size = memory.round_to(environment_variable_data_section_size, sizeof(u64))
	argument_data_section_size = memory.round_to(argument_data_section_size, sizeof(u64))

	total_data_size = sizeof(u64) +                 # Argument count
		arguments.size * sizeof(link) +              # Argument pointers
		sizeof(u64) +                                # 0
		environment_variables.size * sizeof(link) +  # Environment variable pointers
		sizeof(u64) +                                # 0
		argument_data_section_size +                 # Arguments
		environment_variable_data_section_size       # Environment variables

	# Remember to align the stack to 16 bytes
	total_data_size = memory.round_to(total_data_size, 16)

	# Map the stack memory, so that we can produce the startup data
	stack_address_top = mapper.map_kernel_region(physical_stack_address_top - total_data_size, total_data_size)

	# Create pointers to each of the sections
	environment_variable_data = stack_address_top - environment_variable_data_section_size
	argument_data = environment_variable_data - argument_data_section_size
	environment_variable_pointers = argument_data - sizeof(u64) - environment_variables.size * sizeof(link)
	argument_pointers = environment_variable_pointers - sizeof(u64) - arguments.size * sizeof(link)
	argument_count = argument_pointers - sizeof(u64)

	# Add all environment variables
	loop (i = 0, i < environment_variables.size, i++) {
		environment_variable = environment_variables[i]

		# Copy the current environment variable into the environment variable data section
		memory.copy(environment_variable_data, environment_variable.data, environment_variable.length + 1)

		# Add pointer to the environment variable pointers that points to the copied data
		environment_variable_pointers.(link*)[] = environment_variable_data

		# Move over the copied data and the added pointer
		environment_variable_data += environment_variable.length + 1
		environment_variable_pointers += sizeof(link)
	}

	# Add all arguments
	loop (i = 0, i < arguments.size, i++) {
		argument = arguments[i]

		# Copy the current argument into the argument data section
		memory.copy(argument_data, argument.data, argument.length + 1)

		# Add pointer to the argument pointers that points to the copied data
		argument_pointers.(link*)[] = argument_data

		# Move over the copied data and the added pointer
		argument_data += argument.length + 1
		argument_pointers += sizeof(link)
	}

	# Write the number of arguments
	argument_count.(u64*)[] = arguments.size

	return physical_stack_address_top - total_data_size
}