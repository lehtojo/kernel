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
		debug.write_address(program_header.physical_address)
		debug.write(', Physical size = ')
		debug.write(program_header.segment_file_size)
		debug.write(', Memory size = ')
		debug.write_line(program_header.segment_memory_size)

		# Verify the loaded file section exists
		if not is_accessible_region(file, program_header.physical_address, program_header.segment_file_size) or 
			program_header.segment_memory_size > program_header.segment_file_size {
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
		header.type != ELF_OBJECT_FILE_TYPE_EXECUTABLE or 
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
		segment_data = file.data + program_header.physical_address
		segment_size = program_header.segment_memory_size

		# Load the virtual address from the perspective of the program
		program_segment_virtual_address = program_header.virtual_address

		segment_physical_address = PhysicalMemoryManager.instance.allocate_physical_region(segment_size)
		segment_virtual_address = mapper.map_kernel_region(segment_physical_address, segment_size)

		# TODO: Deallocate upon failure

		if segment_physical_address === none {
			debug.write_line('Loader: Failed to allocate memory for a loadable segment')
			failed = true
			stop
		}

		debug.write('Loader: Copying ')
		debug.write(segment_size)
		debug.write(' byte(s) from the executable starting at offset ')
		debug.write_address(program_header.physical_address)
		debug.write(' into virtual address ')
		debug.write_address(program_segment_virtual_address)
		debug.write(' using physical address ')
		debug.write_address(segment_physical_address)
		debug.write_line()

		# Copy the segment data from the file to the allocated segment
		memory.copy(segment_virtual_address, segment_data, segment_size)

		# Add the memory mapping
		output.allocations.add(MemoryMapping.new(
			program_segment_virtual_address as u64,
			segment_physical_address as u64,
			segment_size
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