constant STATIC_ALLOCATOR_START = 0x100000

namespace allocator

import 'C' flush_tlb()

constant INVALID_PHYSICAL_ADDRESS = -1

constant ERROR_INVALID_VIRTUAL_ADDRESS = -1
constant ERROR_OCCUPIED = -2

constant MAX_MEMORY = 2000000000 # 2 GB

#constant L1_COUNT = 1 + (MAX_MEMORY - 1) / 4096
#constant L2_COUNT = 1 + (MAX_MEMORY - 1) / 4096 / 512
#constant L3_COUNT = 1 + (MAX_MEMORY - 1) / 4096 / (512 * 512)
#constant L4_COUNT = 512

constant L1_COUNT = 488448
constant L2_COUNT = 1024
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

# Summary: Returns whether the specified page entry is present
is_present(entry: u64): bool {
	return entry & 1
}

# Summary: Marks the specified page entry present
set_present(entry: u64*) {
	entry[] |= 1
}

# Summary: Returns the physical address stored inside the specified page entry
address_from_page_entry(entry: u64): u64* {
	return entry & 0x7fffffffff000
}

# Summary: Sets the specified page entry writable
set_writable(entry: u64*) {
	entry[] |= 2
}

# Summary: Sets the address of the specified page entry
set_address(entry: u64*, physical_address: link) {
	entry[] |= ((physical_address as u64) & 0x7fffffffff000)
}

to_physical_address(virtual_address: link): link {
	# Virtual address: [L4 9 bits] [L3 9 bits] [L2 9 bits] [L1 9 bits] [Offset 12 bits]
	offset = (virtual_address as u64) & 0xFFF
	l1: u32 = ((virtual_address as u64) |> 12) & 0x1FF
	l2: u32 = ((virtual_address as u64) |> 21) & 0x1FF
	l3: u32 = ((virtual_address as u64) |> 30) & 0x1FF
	l4: u32 = ((virtual_address as u64) |> 39) & 0x1FF

	if l1 >= L1_COUNT or l2 >= L2_COUNT or l3 >= L3_COUNT or l4 >= L4_COUNT return INVALID_PHYSICAL_ADDRESS as link

	l4_entry = L4_BASE.(u64*)[l4]
	if not is_present(l4_entry) return INVALID_PHYSICAL_ADDRESS as link

	l4_entry = address_from_page_entry(l4_entry)[l3]
	if not is_present(l4_entry) return INVALID_PHYSICAL_ADDRESS as link

	l2_entry = address_from_page_entry(l3_entry)[l2]
	if not is_present(l2_entry) return INVALID_PHYSICAL_ADDRESS as link

	l1_entry = address_from_page_entry(l2_entry)[l1]
	if not is_present(l1_entry) return INVALID_PHYSICAL_ADDRESS as link

	return address_from_page_entry(l1_entry) + offset
}

map_page(virtual_address: link, physical_address: link) {
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

	set_address(l4_address, l3_physical_base)
	set_writable(l4_address)
	set_present(l4_address)

	set_address(l3_address, l2_physical_base)
	set_writable(l3_address)
	set_present(l3_address)

	set_address(l2_address, l1_physical_base)
	set_writable(l2_address)
	set_present(l2_address)

	set_address(l1_address, physical_address)
	set_writable(l1_address)
	set_present(l1_address)

	flush_tlb()
}
