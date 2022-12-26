namespace kernel.elf.loader

import kernel.scheduler

# TODO: Could integer overflows be exploited?

access<T>(memory: Array<u8>, offset: u64): Optional<T> {
	if memory.size - offset < sizeof(T) return Optionals.empty<T>()
	return Optionals.new<T>((memory.data + offset) as T)
}

is_accessible_region(memory: Array<u8>, offset: u64, bytes: u64): bool {
	return memory.size - offset >= bytes
}

load_program_headers(file: Array<u8>, program_header_table: link, program_header_count: u16, program_headers: Array<ProgramHeader>): bool {
	# Add all the program headers to the output list
	loop (i = 0, i < program_header_count, i++) {
		program_header = (program_header_table + i * sizeof(ProgramHeader)) as ProgramHeader

		# TODO: Verify virtual region and alignment

		# Verify the loaded file section exists
		if not is_accessible_region(file, program_header.physical_address, program_header.segment_file_size) or 
			program_header.segment_memory_size > program_header.segment_file_size {
			return false
		}

		program_headers[i] = program_header
	}

	return true
}

export load_executable(file: Array<u8>, mappings: List<MemoryMapping>) {
	# Access the file header
	if access<FileHeader>(file, 0) has not header return false

	# Verify the specified file is a ELF-file and that we support it
	if header.magic_number != ELF_MAGIC_NUMBER or 
		header.class != ELF_CLASS_64_BIT or 
		header.endianness != ELF_LITTLE_ENDIAN or 
		header.type != ELF_OBJECT_FILE_TYPE_EXECUTABLE or 
		header.machine != ELF_MACHINE_TYPE_X64 {
		return false
	}

	# Verify the specified file uses the same data structure for program headers
	if header.program_header_size != sizeof(ProgramHeader) return false

	# Verify the program headers exist
	program_header_table = header.program_header_offset
	program_header_count = header.program_header_entry_count
	if not is_accessible_region(file, program_header_table, program_header_count * sizeof(ProgramHeader)) return false

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

		# Allocate memory for the segment
		segment_virtual_address = program_header.virtual_address
		segment_physical_address = KernelHeap.allocate(segment_size)

		# TODO: Deallocate upon failure

		if segment_physical_address === none {
			failed = true
			stop
		}

		# Copy the segment data from the file to the allocated segment
		memory.copy(segment_physical_address, segment_data, segment_size)

		# Add the memory mapping
		mappings.add(MemoryMapping.new(
			segment_virtual_address as u64,
			segment_physical_address as u64,
			segment_size
		))
	}

	# Because the program headers were processed, they are no longer needed
	KernelHeap.deallocate(program_headers_buffer)

	if failed {
		return false
	}

	return true
}