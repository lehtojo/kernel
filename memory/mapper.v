namespace kernel

constant MAP_NO_FLUSH = 1
constant MAP_NO_CACHE = 2
constant MAP_USER = 4
constant MAP_EXECUTABLE = 8

namespace mapper

import kernel.low
import kernel.scheduler

import 'C' flush_tlb()
import 'C' flush_tlb_local(virtual_address: link)

constant PAGE_CONFIGURATION_PRESENT = 1
constant PAGE_CONFIGURATION_WRITABLE = 0b10
constant PAGE_CONFIGURATION_DISABLE_EXECUTION = 1 <| 63

constant INVALID_PHYSICAL_ADDRESS = -1

constant ERROR_INVALID_VIRTUAL_ADDRESS = -1
constant ERROR_OCCUPIED = -2

constant MAX_MEMORY = 0x2000000000 # 128 GB

constant L1_COUNT = MAX_MEMORY / 0x1000
constant L2_COUNT = MAX_MEMORY / (0x1000 * 512)
constant L3_COUNT = 512
constant L4_COUNT = 512

# 0xFFFFFF8000000000
# 0xFF8000000000
constant L4_BASE: link = 0xFFFFFF8000000000 as link
constant L3_BASE: link = (0xFFFFFF8000000000 + L4_COUNT * 8) as link
constant L2_BASE: link = (0xFFFFFF8000000000 + (L4_COUNT + L3_COUNT) * 8) as link
constant L1_BASE: link = (0xFFFFFF8000000000 + (L4_COUNT + L3_COUNT + L2_COUNT) * 8) as link

constant PAGE_MAP_PHYSICAL_ADDRESS = 0x10000000
constant PAGE_MAP_BYTES = (L1_COUNT + L2_COUNT + L3_COUNT + L4_COUNT) * 8

constant PAGE_MAP_VIRTUAL_BASE = 0xFFFFFF8000000000
constant PAGE_MAP_VIRTUAL_MAP_PHYSICAL_ADDRESS = 0xF000000

constant L4_PHYSICAL_BASE: link = (PAGE_MAP_PHYSICAL_ADDRESS) as link
constant L3_PHYSICAL_BASE: link = (PAGE_MAP_PHYSICAL_ADDRESS + L4_COUNT * 8) as link
constant L2_PHYSICAL_BASE: link = (PAGE_MAP_PHYSICAL_ADDRESS + (L4_COUNT + L3_COUNT) * 8) as link
constant L1_PHYSICAL_BASE: link = (PAGE_MAP_PHYSICAL_ADDRESS + (L4_COUNT + L3_COUNT + L2_COUNT) * 8) as link

constant ENTRIES = 512

# Summary: Stores the pages for each CPU used for mapping physical pages
quickmap_physical_base: link

mapper_paging_table: PagingTable

memory_map_end: u64
l4_required_count: u32
l3_required_count: u32
l2_required_count: u32
l1_required_count: u32

# Structure:
# [                                           L4 1                                          ] ... [                                           L4 512                                        ]
# [                  L3 1                   ] ... [                  L3 512                 ]     [                  L3 1                   ] ... [                  L3 512                 ]
# [      L2 1      ] ... [      L2 512      ]     [      L2 1      ] ... [      L2 512      ]     [      L2 1      ] ... [      L2 512      ]     [      L2 1      ] ... [      L2 512      ]
# [L1 1] ... [L 512]     [L1 1] ...  [L1 512]     [L1 1] ... [L 512]     [L1 1] ...  [L1 512]     [L1 1] ... [L 512]     [L1 1] ...  [L1 512]     [L1 1] ... [L 512]     [L1 1] ...  [L1 512]
# | 4K |
# |----- 2 MiB ----|
# |----------------- 1 GiB -----------------|
# |------------------------------------------ 512 GiB --------------------------------------|
# |------------------------------------------------------------------------------------------ 256 TiB --------------------------------------------------------------------------------------|

# [ L4 entries ] [ L3 entries ] [ L2 entries ] [ L1 entries ]
# |              |              |              |
# |              |              |              0xFFFFFF8000000000 + (L4.count + L3.count + L2.count) * 8
# |              |              0xFFFFFF8000000000 + (L4.count + L3.count) * 8
# |              0xFFFFFF8000000000 + L4.count * 8
# 0xFFFFFF8000000000

# M = Maximum usable memory
# Number of L1 entries = 1 + (M - 1) / 4096
# Number of L2 entries = 1 + (M - 1) / 4096 / 512
# Number of L3 entries = 1 + (M - 1) / 4096 / 512^2
# Number of L4 entries = 512 # Use the maximum amount so that we can use the last entry to edit the pages

# Todo: Uefi stuff should not be in this file
add_regions(system_memory_information: SystemMemoryInformation, uefi: UefiInformation): _ {
	debug.write_line('Mapper: Regions:')

	system_memory_information.regions.reserve(uefi.region_count * 2)

	loop (i = 0, i < uefi.region_count, i++) {
		region = uefi.regions[i]
		system_memory_information.regions.add(region)

		if region.type == REGION_AVAILABLE {
			debug.write('Available: ') region.print() debug.write_line()
		} else {
			debug.write('Reserved: ') region.print() debug.write_line()
		}
	}

	debug.write_line('Mapper: All regions added')
}

# Summary:
# Finds a suitable region for the physical memory manager from the specified regions
# and modifies them so that the region gets reserved. Returns the virtual address to the allocated region.
# If no suitable region can be found, this function panics.
allocate_physical_memory_manager(system_memory_information: SystemMemoryInformation): _ {
	# Compute the memory needed by the physical memory manager
	size = sizeof(PhysicalMemoryManager) + PhysicalMemoryManager.LAYER_COUNT * sizeof(Layer) + PhysicalMemoryManager.LAYER_STATE_MEMORY_SIZE

	physical_address = Regions.allocate(system_memory_information.regions, size)

	debug.write('Mapper: Placing physical memory manager at ') debug.write_address(physical_address) debug.write_line()
	system_memory_information.physical_memory_manager_virtual_address = mapper.to_kernel_virtual_address(physical_address)
	memory.zero(system_memory_information.physical_memory_manager_virtual_address, size)
}

# Summary: Finds a suitable region for the boot console framebuffer
initialize_boot_console_framebuffer(allocator: Allocator, system_memory_information: SystemMemoryInformation, uefi: UefiInformation): _ {
	# Compute the memory needed by the physical memory manager
	width = uefi.graphics_information.width
	height = uefi.graphics_information.height
	size = width * height * sizeof(u32)

	physical_address = Regions.allocate(system_memory_information.regions, size)

	if physical_address === none {
		debug.write_line('Mapper: Could not find a suitable region for the boot console framebuffer')
		return
	}

	debug.write('Mapper: Placing boot console framebuffer at ') debug.write_address(physical_address) debug.write_line()

	# Zero out the framebuffer, so we will not have garbage on the screen
	framebuffer = mapper.to_kernel_virtual_address(physical_address)
	memory.zero(framebuffer, size)

	console = FramebufferConsole(framebuffer, width, height) using allocator
	FramebufferConsole.instance = console
}

remap(allocator: Allocator, gdtr_physical_address: link, system_memory_information: SystemMemoryInformation, uefi: UefiInformation): _ {
	debug.write_line('Mapper: Remapping using UEFI data')

	add_regions(system_memory_information, uefi)

	system_memory_information.physical_memory_size = uefi.physical_memory_size
	memory_map_end = uefi.memory_map_end
	debug.write('Mapper: Physical memory size: ') debug.write_address(system_memory_information.physical_memory_size) debug.write_line()
	debug.write('Mapper: Memory map end: ') debug.write_address(memory_map_end) debug.write_line()

	# Compute how many L1s, L2s, L3s and L4s we need for identity mapping
	l4_size = 0x8000000000
	l4_required_count = (memory_map_end + l4_size - 1) / 0x8000000000 # 0x1000*0x200*0x200*0x200
	l3_required_count = (memory_map_end + 0x40000000 - 1) / 0x40000000 # 0x1000*0x200*0x200
	l2_required_count = (memory_map_end + 0x200000 - 1) / 0x200000 # 0x1000*0x200
	l1_required_count = (memory_map_end + 0x1000 - 1) / 0x1000

	# We will always allocate all L4s, because they do not require a lot of memory and we want to use entry at index 0x100 as kernel mapping
	l4_count = 512
	l3_count = 256 * 512 # Todo: Explain
	l2_count = memory.round_to(l2_required_count, 512)
	l1_count = memory.round_to(l1_required_count, 512)

	# Compute how much memory we need to allocate for the page map
	size = memory.round_to_page((l4_count + l3_count + l2_count + l1_count) * sizeof(u64))

	debug.write('Mapper: Allocating ')
	debug.write(size)
	debug.write_line(' bytes for the page map')

	# l4_base = 0xffffffffffffffff
	l4_base = Regions.allocate(system_memory_information.regions, size) as u64
	memory.zero(l4_base as link, size)

	debug.write('Mapper: Kernel page table = ')
	debug.write_address(l4_base)
	debug.write_line()

	debug.write_line('Mapper: Identity mapping...')

	# Compute where each layer starts
	l3_base = l4_base + l4_count * sizeof(u64)
	l2_base = l3_base + l3_count * sizeof(u64)
	l1_base = l2_base + l2_count * sizeof(u64)

	# Map the kernel
	# Todo: Explain
	loop (i = 0, i < 256, i++) {
		address = l3_base + i * (512 * sizeof(u64))
		l4_base.(u64*)[KERNEL_MAP_BASE_L4 + i] = address | 0b11
	}

	# Identity map L4
	loop (i = 0, i < l4_required_count, i++) {
		address = l3_base + i * (512 * sizeof(u64))
		l4_base.(u64*)[i] = address | 0b11
	}

	# Identity map L3
	loop (i = 0, i < l3_required_count, i++) {
		address = l2_base + i * (512 * sizeof(u64))
		l3_base.(u64*)[i] = address | 0b11
	}

	# Identity map L2
	loop (i = 0, i < l2_required_count, i++) {
		address = l1_base + i * (512 * sizeof(u64))
		l2_base.(u64*)[i] = address | 0b11
	}

	# Identity map L1
	loop (i = 0, i < l1_required_count, i++) {
		address = i * 0x1000
		l1_base.(u64*)[i] = address | 0b11
	}

	# Unmap the first page as we do not need it and it is reserved for "none" (null)
	l1_base.(u64*)[] = 0

	debug.write_line('Mapper: Switching to the kernel paging table...')

	# Use the new page mapping
	mapper_paging_table = (KERNEL_MAP_BASE + l4_base) as PagingTable
	write_cr3(l4_base as u64)

	# gdtr_virtual_address = GDTR_VIRTUAL_ADDRESS + (gdtr_physical_address as u64) % PAGE_SIZE
	gdtr_virtual_address = KERNEL_MAP_BASE + gdtr_physical_address as u64

	debug.write_line('Mapper: Mapping GDT to the kernel paging table...')

	# Remap the GDT to the virtual address that is used by process paging tables.
	# mapper_paging_table.map_gdt(HeapAllocator.instance, gdtr_physical_address)

	# Apply the changes to paging
	flush_tlb()

	# Update the address of GDTR
	debug.write('Mapper: Switching GDTR to ')
	debug.write_address(gdtr_virtual_address)
	debug.write_line()

	write_gdtr(gdtr_virtual_address)

	allocate_physical_memory_manager(system_memory_information)
	initialize_boot_console_framebuffer(allocator, system_memory_information, uefi)

	debug.write_line('Mapper: Cleaning regions...')
	Regions.clean(system_memory_information.regions)

	debug.write_line('Mapper: Finding reserved regions...')
	Regions.find_reserved_physical_regions(system_memory_information.regions, system_memory_information.physical_memory_size, system_memory_information.reserved)
	debug.write_line('Mapper: Remapping is complete')
}

# Summary:
# Removes the first 1 GiB identity mapping from the paging tables.
# Remaps the GDTR to the virtual address that is used by process paging tables. 
remap() {
	# Disable identity mapping of the first 1 GiB.
	# Use high virtual address mapping for the kernel from now on.
	# We can not map the kernel to the first 1 GiB for example, 
	# because it is generally reserved for user applications. 
	# However, the kernel must be mapped to the same virtual address region in each process 
	# so that we do not have to switch page tables during system calls.
	# l4_base = L4_BASE
	# l4_base.(u64*)[] = 0 # Todo: Revert

	# Apply the changes to paging
	# flush_tlb()	

	# gdtr_physical_address = Processor.current.gdtr_physical_address
	# gdtr_virtual_address = GDTR_VIRTUAL_ADDRESS + (gdtr_physical_address as u64) % PAGE_SIZE

	# Remap the GDT to the virtual address that is used by process paging tables.
	# paging_table = mapper.map_kernel_page(read_cr3() as link, MAP_NO_CACHE) as scheduler.PagingTable
	# paging_table.map_gdt(HeapAllocator.instance, gdtr_physical_address)

	# Apply the changes to paging
	# flush_tlb()

	# Update the address of GDTR
	# debug.write('Mapper: Switching GDTR to ')
	# debug.write_address(gdtr_virtual_address)
	# debug.write_line()

	# write_gdtr(gdtr_virtual_address)
}

# Summary: Returns the memory region that the mapper uses
region(): Segment {
	start = (PAGE_MAP_VIRTUAL_MAP_PHYSICAL_ADDRESS) as link
	end = (PAGE_MAP_PHYSICAL_ADDRESS + PAGE_MAP_BYTES) as link
	return Segment.new(REGION_RESERVED, start, end)
}

# Summary: Maps the kernel regions from the current paging tables to the specified L4 entries
map_kernel(entries: u64*) {
	debug.write_line('Mapper: Mapping kernel...')

	# Map the kernel
	# Todo: Explain
	loop (i = 0, i < 256, i++) {
		entries[KERNEL_MAP_BASE_L4 + i] = mapper_paging_table.entries[KERNEL_MAP_BASE_L4 + i]
	}

	# Todo: Remove these commented regions such as this and others below
	###
	# Todo: Fix the compiler bug: If L4_BASE is used directly, the compiler tries to inline the constant address into an instruction as a 32-bit address.  
	l4_base = L4_BASE

	kernel_entry = l4_base.(u64*)[KERNEL_MAP_BASE_L4]
	entries[KERNEL_MAP_BASE_L4] = (kernel_entry & (!0b111100000))

	kernel_map_editor_entry = l4_base.(u64*)[ENTRIES - 1]
	entries[ENTRIES - 1] = (kernel_map_editor_entry & (!0b111100000))
	###
}

# Summary: Returns whether the specified page entry is present
is_present(entry: u64): bool {
	return entry & PAGE_CONFIGURATION_PRESENT
}

# Summary: Marks the specified page entry present
set_present(entry: u64*) {
	entry[] |= PAGE_CONFIGURATION_PRESENT
}

# Summary: Returns the physical address stored inside the specified page entry
address_from_page_entry(entry: u64): u64* {
	return (entry & 0x7fffffffff000) as u64*
}

# Summary: Returns the physical address stored inside the specified page entry
virtual_address_from_page_entry(entry: u64): u64* {
	physical_address = entry & 0x7fffffffff000
	return (KERNEL_MAP_BASE + physical_address) as u64*
}

# Summary: Sets the accessiblity of the specified page entry
set_accessibility(entry: u64*, all: bool) {
	if all {
		entry[] |= 0b100
	} else {
		entry[] &= !0b100
	}
}

# Summary: Sets the specified page entry writable
set_writable(entry: u64*) {
	entry[] |= PAGE_CONFIGURATION_WRITABLE
}

# Summary: Returns whether the page is writable
is_writable(entry: u64): bool {
	return (entry & PAGE_CONFIGURATION_WRITABLE) != 0
}

# Summary: Controls caching of the specified page entry
set_cached(entry: u64*, cache: bool) {
	if cache {
		entry[] &= !0b10000
	} else {
		entry[] |= 0b10000
	}
}

# Summary: Sets the address of the specified page entry
set_address(entry: u64, physical_address: link) {
	return (entry & (!0x7fffffffff000)) | ((physical_address as u64) & 0x7fffffffff000)
}

# Summary: Sets the address of the specified page entry
set_address(entry: u64*, physical_address: link) {
	current = entry[] & (!0x7fffffffff000)
	entry[] = current | ((physical_address as u64) & 0x7fffffffff000)
}

# Summary: Controls whether the specified page can be executed
set_executable(entry: u64*, executable: bool) {
	if executable {
		entry[] &= !PAGE_CONFIGURATION_DISABLE_EXECUTION
	} else {
		entry[] |= PAGE_CONFIGURATION_DISABLE_EXECUTION
	}
}

to_physical_address(virtual_address: link): link {
	maybe_physical_address = mapper_paging_table.to_physical_address(virtual_address)
	if maybe_physical_address has physical_address return physical_address

	panic('Kernel virtual address was not mapped')

	###
	# Virtual address: [L4 9 bits] [L3 9 bits] [L2 9 bits] [L1 9 bits] [Offset 12 bits]
	offset = virtual_address & 0xFFF
	l1 = ((virtual_address |> 12) & 0b111111111) as u32
	l2 = ((virtual_address |> 21) & 0b111111111) as u32
	l3 = ((virtual_address |> 30) & 0b111111111) as u32
	l4 = ((virtual_address |> 39) & 0b111111111) as u32

	l4_base = L4_BASE
	l4_entry = l4_base.(u64*)[l4]
	if not is_present(l4_entry) panic('Virtual address was not mapped (L4)')

	l3_entry = virtual_address_from_page_entry(l4_entry)[l3]
	if not is_present(l3_entry) panic('Virtual address was not mapped (L3)')

	l2_entry = virtual_address_from_page_entry(l3_entry)[l2]
	if not is_present(l2_entry) panic('Virtual address was not mapped (L2)')

	l1_entry = virtual_address_from_page_entry(l2_entry)[l1]
	if not is_present(l1_entry) panic('Virtual address was not mapped (L1)')

	return address_from_page_entry(l1_entry) + offset
	###
}

to_kernel_virtual_address(physical_address: link): link {
	return KERNEL_MAP_BASE as link + physical_address as u64
}

to_kernel_virtual_address(physical_address: u64): link {
	return KERNEL_MAP_BASE as link + physical_address
}

map_page(virtual_address: link, physical_address: link, flags: u32): link {
	mapper_paging_table.map_page(HeapAllocator.instance, virtual_address, physical_address, flags)
	return virtual_address
	###
	require((virtual_address & (PAGE_SIZE - 1)) == 0, 'Virtual address was not aligned correctly upon mapping')
	require((physical_address & (PAGE_SIZE - 1)) == 0, 'Physical address was not aligned correctly upon mapping')

	# Virtual address: [L4 9 bits] [L3 9 bits] [L2 9 bits] [L1 9 bits] [Offset 12 bits]
	l1: u32 = ((virtual_address as u64) |> 12) & 0x1FF
	l2: u32 = ((virtual_address as u64) |> 21) & 0x1FF
	l3: u32 = ((virtual_address as u64) |> 30) & 0x1FF
	l4: u32 = ((virtual_address as u64) |> 39) & 0x1FF

	if l1 >= L1_COUNT or l2 >= L2_COUNT or l3 >= L3_COUNT or l4 >= L4_COUNT return ERROR_INVALID_VIRTUAL_ADDRESS as link

	l4_physical_base = L4_PHYSICAL_BASE
	l3_physical_base = L3_PHYSICAL_BASE + l4 * 0x1000
	l2_physical_base = L2_PHYSICAL_BASE + l4 * 0x200000 + l3 * 0x1000
	l1_physical_base = L1_PHYSICAL_BASE + l4 * 0x40000000 + l3 * 0x200000 + l2 * 0x1000

	l4_base = L4_BASE
	l3_base = L3_BASE + l4 * 0x1000
	l2_base = L2_BASE + l4 * 0x200000 + l3 * 0x1000
	l1_base = L1_BASE + l4 * 0x40000000 + l3 * 0x200000 + l2 * 0x1000

	l4_address = l4_base + l4 * 8
	l3_address = l3_base + l3 * 8
	l2_address = l2_base + l2 * 8
	l1_address = l1_base + l1 * 8

	# Todo:
	# Can not map L4 entries, because other entries than the kernel entry would get mapped.
	# Rename thing so that this makes sense.
	#set_address(l4_address, l3_physical_base)
	#set_writable(l4_address)
	#set_present(l4_address)

	set_address(l3_address, l2_physical_base)
	set_writable(l3_address)
	set_present(l3_address)

	set_address(l2_address, l1_physical_base)
	set_writable(l2_address)
	set_present(l2_address)

	set_address(l1_address, physical_address)
	set_writable(l1_address)
	set_cached(l1_address, not has_flag(flags, MAP_NO_CACHE))
	set_accessibility(l1_address, has_flag(flags, MAP_USER))
	set_present(l1_address)

	if not has_flag(flags, MAP_NO_FLUSH) flush_tlb()

	return virtual_address
	###
}

map_page(virtual_address: link, physical_address: link): link {
	return map_page(virtual_address, physical_address, 0)
}

map_region(virtual_address_start: link, physical_address_start: link, size: u64, flags: u32): link {
	mapper_paging_table.map_region(HeapAllocator.instance, MemoryMapping.new(virtual_address_start as u64, physical_address_start as u64, size), flags)
	return virtual_address_start & (-PAGE_SIZE)
	###
	physical_page = physical_address_start & (-PAGE_SIZE)
	virtual_page = virtual_address_start & (-PAGE_SIZE)
	last_physical_page = memory.round_to_page(physical_address_start + size)
	last_virtual_page = memory.round_to_page(virtual_address_start + size)

	debug.write('Mapping region ')
	debug.write_address(physical_page) debug.put(`-`) debug.write_address(last_physical_page + PAGE_SIZE)
	debug.write(' to ')
	debug.write_address(virtual_page) debug.put(`-`) debug.write_address(last_virtual_page + PAGE_SIZE)
	debug.write_line()

	loop (physical_page < last_physical_page) {
		map_page(virtual_page, physical_page, flags | MAP_NO_CACHE)

		physical_page += PAGE_SIZE
		virtual_page += PAGE_SIZE
	}

	if not has_flag(flags, MAP_NO_CACHE) flush_tlb()

	return virtual_address_start & (-PAGE_SIZE) # Warning: Should not we return the unaligned virtual address?
	###
}

map_region(virtual_address_start: link, physical_address_start: link, size: u64): link {
	return map_region(virtual_address_start, physical_address_start, size, 0)
}

map_kernel_page(physical_address: link): link {
	map_page(KERNEL_MAP_BASE as link + physical_address, physical_address)
	return KERNEL_MAP_BASE as link + physical_address as u64
}

map_kernel_region(physical_address: link, size: u64): link {
	map_region(KERNEL_MAP_BASE as link + physical_address, physical_address, size)
	return KERNEL_MAP_BASE as link + physical_address as u64
}

map_kernel_page(physical_address: link, flags: u32): link {
	map_page(KERNEL_MAP_BASE as link + physical_address, physical_address, flags)
	return KERNEL_MAP_BASE as link + physical_address as u64
}

map_kernel_region(physical_address: link, size: u64, flags: u32): link {
	map_region(KERNEL_MAP_BASE as link + physical_address, physical_address, size, flags)
	return KERNEL_MAP_BASE as link + physical_address as u64
}

# Summary:
# Maps the specified physical address to a specific virtual page and 
# do not flush the paging tables, instead only update the mapped page.
# Because only a specific virtual page is used, future calls will remove the mapping.
# Returns the virtual address that can be used to access the specified physical address.
quickmap(physical_address: link): link {
	return map_kernel_page(physical_address)

	# Use the quickmap page of the current CPU
	cpu = 0 # TODO: Use the cpu id
	quickmap_page = quickmap_physical_base + cpu * PAGE_SIZE

	# Map the virtual page to the specified physical address, but do not flush, because that would not be quick
	map_page(quickmap_page, physical_address, MAP_NO_CACHE | MAP_NO_FLUSH)

	# Instead, update only the mapped page
	virtual_address = KERNEL_MAP_BASE as link + quickmap_page
	#flush_tlb_local(virtual_address)
	flush_tlb()

	debug.write('Quickmapped ')
	debug.write_address(physical_address)
	debug.write(' to ')
	debug.write_address(virtual_address)
	debug.write_line()

	return virtual_address
}

# Summary:
# Maps the specified physical address to a specific virtual page and 
# do not flush the paging tables, instead only update the mapped page.
# Because only a specific virtual page is used, future calls will remove the mapping. 
# Returns the virtual address that can be used to access the specified physical address.
quickmap<T>(physical_address: link): T {
	return quickmap(physical_address) as T
}