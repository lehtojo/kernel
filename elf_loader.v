namespace kernel.elf.loader

import kernel.scheduler

plain LoadInformation {
	allocations: List<Segment>
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

# Summary:
# Copies one page from the data to the destination while taking into account the paging table.
# If the destination page is already mapped to physical memory, the mapped physical memory will be used.
# Otherwise new physical page will be allocated and mapped for copying.
copy_page(allocator: Allocator, paging_table: PagingTable, unaligned_virtual_destination: u64, source: link, remaining: u64): u64 {
	# Compute the next virtual page starting from the specified virtual address
	next_virtual_page = memory.round_to_page(unaligned_virtual_destination)
	if next_virtual_page == unaligned_virtual_destination { next_virtual_page += PAGE_SIZE }

	# Compute the number of bytes that should be copied:
	# - Copy the number of bytes that will reach the next page
	# - Do not copy bytes more than there are remaining
	size = math.min(next_virtual_page - unaligned_virtual_destination, remaining)

	# Todo: Do we need to check permissions here or is everything verified before this function is called?
	mapped_unaligned_physical_page = none as link

	# Use existing physical memory when possible
	if paging_table.to_physical_address(unaligned_virtual_destination as link) has existing_physical_page {
		# Map the exiting physical memory into kernel space, so that we can copy into it
		debug.write_line('Loader: Using existing physical page for program section ')
		debug.write_address(existing_physical_page)
		debug.write_line()
		mapped_unaligned_physical_page = mapper.map_kernel_region(existing_physical_page, size)

	} else {
		# Compute the address of the page where we will copy data
		virtual_page = memory.page_of(unaligned_virtual_destination) as link

		# Compute the offset inside virtual page
		offset = unaligned_virtual_destination as u64 - virtual_page as u64

		# Since no physical memory is mapped, we need to allocate it
		new_physical_page = PhysicalMemoryManager.instance.allocate_physical_region(PAGE_SIZE)

		# Map the new page to the paging table
		paging_table.map_page(allocator, virtual_page, new_physical_page)

		# Map the new physical memory into kernel space, so that we can copy into it
		mapped_unaligned_physical_page = mapper.map_kernel_region(new_physical_page, size) + offset
	}

	# Copy the data into the physical memory
	memory.copy(mapped_unaligned_physical_page, source, size)

	# Return the number of bytes copied
	return size
}

export load_executable(allocator: Allocator, paging_table: PagingTable, file: Array<u8>, output: LoadInformation): bool {
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
		# Load only the loadable segments into memory
		program_header = program_headers[i]
		if program_header.type != ELF_SEGMENT_TYPE_LOADABLE and program_header.type != ELF_SEGMENT_TYPE_DYNAMIC continue

		destination_virtual_address = program_header.virtual_address
		source_data = file.data + program_header.offset
		remaining = math.min(program_header.segment_file_size, program_header.segment_memory_size) # Determine how many bytes should be copied from the file into memory

		debug.write('Loader: Copying ')
		debug.write(remaining)
		debug.write(' byte(s) from the executable starting at offset ')
		debug.write_address(program_header.offset)
		debug.write(' into virtual address ')
		debug.write_address(destination_virtual_address)
		debug.write_line()

		# Determine the type of this segment
		segment_type = PROCESS_ALLOCATION_PROGRAM_DATA
		if has_flag(program_header.flags, ELF_SEGMENT_FLAG_EXECUTE) { segment_type = PROCESS_ALLOCATION_PROGRAM_TEXT }

		# Add the memory mapping to allocations
		start_virtual_address = memory.page_of(destination_virtual_address) as link
		end_virtual_address = memory.round_to_page(destination_virtual_address + remaining) as link
		output.allocations.add(Segment.new(segment_type, start_virtual_address, end_virtual_address))

		# Copy pages from the executable until there is no data left
		loop (remaining > 0) {
			copied = copy_page(allocator, paging_table, destination_virtual_address, source_data, remaining)

			destination_virtual_address += copied
			source_data += copied
			remaining -= copied
		}
	}

	# Because the program headers were processed, they are no longer needed
	KernelHeap.deallocate(program_headers_buffer)

	if failed return false

	# Register the entry point
	# TODO: Verify the entry point is inside an executable region
	output.entry_point = header.entry
	return true
}

# Summary:
# Copies process startup data such as arguments and environment arguments to the top of the stack.
# Returns the number of copied bytes so that the caller can adjust the stack pointer.
export load_stack_startup_data(stack_physical_address_top: u64, stack_virtual_address_top: u64, arguments: List<String>, environment_variables: List<String>): u64 {
	# Todo: If there are a lot of arguments and environment variables, stack can overflow

	# Compute the number of bytes needed for the startup data:
	# 0                                  8 (bytes)
	# +----------------------------------+ <--+
	# |                                  |    |
	# | Environment variable string data |    |
	# |                                  |    |
	# +----------------------------------+    |   Startup data section (16 byte aligned)
	# |                                  |    |
	# |      Argument string data        |    |
	# |                                  |    |
	# +----------------------------------+ <--+
	# |             Padding              |        Padding to make the whole startup data 16 byte aligned
	# +----------------------------------+
	# |                                  |
	# |        Auxiliary vector          |        Aligned to 16 bytes
	# |                                  |
	# +----------------------------------+
	# |                0                 |
	# +----------------------------------+ 
	# |     Environment variable n       |
	# |               ...                |
	# |     Environment variable 3       |
	# |     Environment variable 2       |
	# |     Environment variable 1       |
	# +----------------------------------+ 
	# |                0                 |
	# +----------------------------------+
	# |            Argument n            |
	# |               ...                |
	# |            Argument 3            |
	# |            Argument 2            |
	# |            Argument 1            |
	# +----------------------------------+
	# |          Argument count          |
	# +----------------------------------+ <--- rsp

	# Compute the number of bytes required for the first two sections
	environment_variable_data_section_size = 0
	argument_data_section_size = 0
	loop (i = 0, i < environment_variables.size, i++) { environment_variable_data_section_size += environment_variables[i].length + 1 }
	loop (i = 0, i < arguments.size, i++) { argument_data_section_size += arguments[i].length + 1 }

	# Ensure the sections sizes are multiple of 16 bytes
	environment_variable_data_section_size = memory.round_to(environment_variable_data_section_size, 16)
	argument_data_section_size = memory.round_to(argument_data_section_size, 16)

	# All of the startup data must be 16 byte aligned.
	# Since the startup data section is aligned to 16 bytes, we must take care of the other data below it.
	# All of the data below the data section are 8 byte entries, so we need to add an extra 8 byte padding if there are odd number of entries.
	entry_count = 3 + environment_variables.size + arguments.size
	padding = entry_count % 2 * sizeof(u64)

	# Todo: Implement this
	auxiliary_vector_size = 64
	require(auxiliary_vector_size % 16 == 0, 'Auxiliary vector was not aligned to 16 bytes')

	total_data_size = sizeof(u64) +                 # Argument count
		arguments.size * sizeof(link) +              # Argument pointers
		sizeof(u64) +                                # 0
		environment_variables.size * sizeof(link) +  # Environment variable pointers
		sizeof(u64) +                                # 0
		auxiliary_vector_size +                      # Auxiliary vector
		padding +                                    # Padding
		argument_data_section_size +                 # Arguments
		environment_variable_data_section_size       # Environment variables

	require(total_data_size % 16 == 0, 'Startup data was not aligned to 16 bytes')

	# Map the stack memory, so that we can produce the startup data
	mapped_stack_address_top = mapper.map_kernel_region(stack_physical_address_top as link - total_data_size, total_data_size) + total_data_size

	# Create pointers for writing into the startup data
	mapped_environment_variable_data = mapped_stack_address_top - environment_variable_data_section_size
	mapped_argument_data = mapped_environment_variable_data - argument_data_section_size
	mapped_environment_variable_pointers = mapped_argument_data - padding - auxiliary_vector_size - sizeof(u64) - environment_variables.size * sizeof(link)
	mapped_argument_pointers = mapped_environment_variable_pointers - sizeof(u64) - arguments.size * sizeof(link)
	mapped_argument_count = mapped_argument_pointers - sizeof(u64)

	# Create pointers into the data section that the process can use
	virtual_environment_variable_data = stack_virtual_address_top - environment_variable_data_section_size
	virtual_argument_data = virtual_environment_variable_data - argument_data_section_size

	# Add all environment variables
	loop (i = 0, i < environment_variables.size, i++) {
		environment_variable = environment_variables[i]

		# Copy the current environment variable into the environment variable data section
		memory.copy(mapped_environment_variable_data, environment_variable.data, environment_variable.length + 1)

		# Add pointer to the environment variable pointers that points to the copied data
		mapped_environment_variable_pointers.(link*)[] = virtual_environment_variable_data as link

		# Move over the copied data and the added pointer
		mapped_environment_variable_data += environment_variable.length + 1
		virtual_environment_variable_data += environment_variable.length + 1
		mapped_environment_variable_pointers += sizeof(link)
	}

	# Add all arguments
	loop (i = 0, i < arguments.size, i++) {
		argument = arguments[i]

		# Copy the current argument into the argument data section
		memory.copy(mapped_argument_data, argument.data, argument.length + 1)

		# Add pointer to the argument pointers that points to the copied data
		mapped_argument_pointers.(link*)[] = virtual_argument_data as link

		# Move over the copied data and the added pointer
		mapped_argument_data += argument.length + 1
		virtual_argument_data += argument.length + 1
		mapped_argument_pointers += sizeof(link)
	}

	# Write the number of arguments
	mapped_argument_count.(u64*)[] = arguments.size

	return total_data_size
}