namespace kernel.mapper

import 'C' flush_tlb()
import 'C' flush_tlb_local(virtual_address: link)

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
constant L4_BASE: link = 0xFFFFFF8000000000
constant L3_BASE: link = 0xFFFFFF8000000000 + L4_COUNT * 8
constant L2_BASE: link = 0xFFFFFF8000000000 + (L4_COUNT + L3_COUNT) * 8
constant L1_BASE: link = 0xFFFFFF8000000000 + (L4_COUNT + L3_COUNT + L2_COUNT) * 8

constant PAGE_MAP_PHYSICAL_ADDRESS = 0x10000000
constant PAGE_MAP_BYTES = (L1_COUNT + L2_COUNT + L3_COUNT + L4_COUNT) * 8

constant PAGE_MAP_VIRTUAL_BASE = 0xFFFFFF8000000000
constant PAGE_MAP_VIRTUAL_MAP_PHYSICAL_ADDRESS = 0xF000000

constant L4_PHYSICAL_BASE: link = PAGE_MAP_PHYSICAL_ADDRESS
constant L3_PHYSICAL_BASE: link = PAGE_MAP_PHYSICAL_ADDRESS + L4_COUNT * 8
constant L2_PHYSICAL_BASE: link = PAGE_MAP_PHYSICAL_ADDRESS + (L4_COUNT + L3_COUNT) * 8
constant L1_PHYSICAL_BASE: link = PAGE_MAP_PHYSICAL_ADDRESS + (L4_COUNT + L3_COUNT + L2_COUNT) * 8

constant ENTRIES = 512

# Summary: Stores the pages for each CPU used for mapping physical pages
quickmap_physical_base: link

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
	l4_base = L4_BASE
	l4_base.(u64*)[] = 0

	# Apply the changes to paging
	flush_tlb()	

	gdtr_physical_address = Processor.current.gdtr_physical_address
	gdtr_virtual_address = GDTR_VIRTUAL_ADDRESS + (gdtr_physical_address as u64) % PAGE_SIZE

	# Remap the GDT to the virtual address that is used by process paging tables.
	paging_table = mapper.map_kernel_page(read_cr3() as link) as scheduler.PagingTable
	paging_table.map_gdt(HeapAllocator.instance, gdtr_physical_address)

	# Apply the changes to paging
	flush_tlb()

	# Update the address of GDTR
	debug.write('Mapper: Switching GDTR to ')
	debug.write_address(gdtr_virtual_address)
	debug.write_line()

	write_gdtr(gdtr_virtual_address)
}

# Summary: Returns the memory region that the mapper uses
region(): Segment {
	start: link = PAGE_MAP_VIRTUAL_MAP_PHYSICAL_ADDRESS
	end: link = PAGE_MAP_PHYSICAL_ADDRESS + PAGE_MAP_BYTES
	return Segment.new(REGION_RESERVED, start, end)
}

# Summary: Maps the kernel regions from the current paging tables to the specified L4 entries
map_kernel_entry(entries: u64*) {
	# Todo: Fix the compiler bug: If L4_BASE is used directly, the compiler tries to inline the constant address into an instruction as a 32-bit address.  
	l4_base = L4_BASE

	kernel_entry = l4_base.(u64*)[KERNEL_MAP_BASE_L4]
	entries[KERNEL_MAP_BASE_L4] = (kernel_entry & (!0b111100000))
}

# Summary: Returns whether the specified page entry is present
is_present(entry: u64): bool {
	return entry & 1
}

# Summary: Marks the specified page entry present
set_present(entry: u64*) {
	entry[] |= 1

	# Todo: Remove
	entry[] |= 4
	entry[] |= 1
	entry[] |= 16
}

# Summary: Returns the physical address stored inside the specified page entry
address_from_page_entry(entry: u64): u64* {
	return entry & 0x7fffffffff000
}

# Summary: Returns the physical address stored inside the specified page entry
virtual_address_from_page_entry(entry: u64): u64* {
	physical_address: link = entry & 0x7fffffffff000
	return map_kernel_page(physical_address) as u64*
}

# Summary: Sets the specified page entry writable
set_writable(entry: u64*) {
	entry[] |= 2
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
set_address(entry: u64*, physical_address: link) {
	entry[] |= ((physical_address as u64) & 0x7fffffffff000)
}

to_physical_address(virtual_address: link): link {
	# Virtual address: [L4 9 bits] [L3 9 bits] [L2 9 bits] [L1 9 bits] [Offset 12 bits]
	offset = virtual_address & 0xFFF
	l1: u32 = (virtual_address |> 12) & 0b111111111
	l2: u32 = (virtual_address |> 21) & 0b111111111
	l3: u32 = (virtual_address |> 30) & 0b111111111
	l4: u32 = (virtual_address |> 39) & 0b111111111

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
}

to_kernel_virtual_address(physical_address: link): link {
	return KERNEL_MAP_BASE as link + physical_address as u64
}

to_kernel_virtual_address(physical_address: u64): link {
	return KERNEL_MAP_BASE as link + physical_address
}

map_page(virtual_address: link, physical_address: link, cache: bool, flush: bool): link {
	require((virtual_address & (PAGE_SIZE - 1)) == 0, 'Virtual address was not aligned correctly upon mapping')
	require((physical_address & (PAGE_SIZE - 1)) == 0, 'Physical address was not aligned correctly upon mapping')

	# Virtual address: [L4 9 bits] [L3 9 bits] [L2 9 bits] [L1 9 bits] [Offset 12 bits]
	l1: u32 = ((virtual_address as u64) |> 12) & 0x1FF
	l2: u32 = ((virtual_address as u64) |> 21) & 0x1FF
	l3: u32 = ((virtual_address as u64) |> 30) & 0x1FF
	l4: u32 = ((virtual_address as u64) |> 39) & 0x1FF

	if l1 >= L1_COUNT or l2 >= L2_COUNT or l3 >= L3_COUNT or l4 >= L4_COUNT return ERROR_INVALID_VIRTUAL_ADDRESS

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
	set_present(l1_address)
	set_cached(l1_address, cache)

	if flush flush_tlb()

	return virtual_address
}

map_page(virtual_address: link, physical_address: link): link {
	return map_page(virtual_address, physical_address, true, true)
}

map_region(virtual_address_start: link, physical_address_start: link, size: u64): link {
	physical_page = physical_address_start & (-PAGE_SIZE)
	virtual_page = virtual_address_start & (-PAGE_SIZE)
	last_physical_page = (virtual_address_start + size) & (-PAGE_SIZE)
	last_virtual_page = (physical_address_start + size) & (-PAGE_SIZE)

	debug.write('Mapping region ')
	debug.write_address(physical_page) debug.put(`-`) debug.write_address(last_physical_page + PAGE_SIZE)
	debug.write(' to ')
	debug.write_address(virtual_page) debug.put(`-`) debug.write_address(last_virtual_page + PAGE_SIZE)
	debug.write_line()

	loop (physical_page <= last_physical_page) {
		map_page(virtual_page, physical_page, true, false)

		physical_page += PAGE_SIZE
		virtual_page += PAGE_SIZE
	}

	flush_tlb()

	return virtual_address_start & (-PAGE_SIZE) # Warning: Should not we return the unaligned virtual address?
}

map_kernel_page(physical_address: link): link {
	map_page(physical_address, physical_address)
	return KERNEL_MAP_BASE as link + physical_address as u64
}

map_kernel_region(physical_address: link, size: u64): link {
	map_region(physical_address, physical_address, size)
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
	map_page(quickmap_page, physical_address, false, false)

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