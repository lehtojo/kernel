PhysicalMemoryManagerAvailableLayerElement {
	next: PhysicalMemoryManagerAvailableLayerElement
	previous: PhysicalMemoryManagerAvailableLayerElement
}

PhysicalMemoryManagerLayer {
	depth: u32
	upper: PhysicalMemoryManagerLayer
	lower: PhysicalMemoryManagerLayer

	states: link
	size: u64

	next: PhysicalMemoryManagerAvailableLayerElement
	last: PhysicalMemoryManagerAvailableLayerElement

	# Summary:
	# Splits slabs towards the specified physical address down to the specified depth.
	# Allocates the lowest slab containing the specified physical address.
	split(physical_address: link, to: u32): link {
		slab: link = (physical_address as u64) & (-size)

		# Stop when the target depth is reached
		if depth == to {
			index = (slab as u64) / size
			set_unavailable(index)
			return slab
		}

		if is_split(slab) {
			# Since the slab on the current layer is already split, continue lower
			return lower.split(physical_address, to)
		}

		index = (slab as u64) / size
		require(is_available(index), 'Can not split an unavailable slab')

		# Since we are splitting the specified slab, it must be set unavailable
		remove(slab as PhysicalMemoryManagerAvailableLayerElement)
		set_unavailable(index)

		# Compute the addresses of the two lower layer slabs
		slab = physical_address & (-lower.size)
		buddy = ((slab as u64) ¤ lower.size) as link

		# Set the buddy slab available on the lower layer
		lower.add(buddy)

		# Since we have not reached the target depth, continue lower
		return lower.split(physical_address, to)
	}

	# Summary:
	# Returns whether the specified slab is split
	is_split(slab: link) {
		require((slab & (size - 1)) == 0, 'Illegal slab address')

		# If there is no lower layer, the slab can not be split
		if lower === none return false

		#                                          Cases
		#
		# ... ================================== ... | ... ================================== ...
		# ... |               1                | ... | ... |               1                | ...
		# ... ================================== ... | ... ================================== ...
		# ... |       1       | ... <-- Unsplit      | ... |       1       | ... <-- Split   
		# ... ================= ...                  | ... ================= ...                 
		# ... |   0   |   0   | ...                  | ... |   1   |   0   | ...                 
		# ... ================= ...                  | ... ================= ...                 
		#                                            |
		# ... ================================== ... | ... ================================== ... 
		# ... |               1                | ... | ... |               1                | ... 
		# ... ================================== ... | ... ================================== ... 
		# ... |       1       | ... <-- Split        | ... |       1       | ... <-- Split        
		# ... ================= ...                  | ... ================= ...                  
		# ... |   0   |   1   | ...                  | ... |   1   |   1   | ...                  
		# ... ================= ...                  | ... ================= ...                  

		# If the slab on this layer is split, it must be unavailable
		index = (slab as u64) / size
		if is_available(index) return false

		# If either one of the lower level slabs is unavailable, the slab on this layer must be split
		left = index * 2
		right = left + 1

		return not lower.is_available(left) or not lower.is_available(right)
	}

	# Summary: Returns whether the specified entry is available
	is_available(index: u64): bool {
		byte = index / 8
		bit = index - byte * 8

		return ((states[byte] |> bit) & 1) == 0
	}

	# Summary: Sets the specified entry available
	set_available(index: u64) {
		byte = index / 8
		bit = index - byte * 8

		states[byte] &= (!(1 <| bit))
	}

	# Summary: Sets the specified entry unavailable
	set_unavailable(index: u64) {
		byte = index / 8
		bit = index - byte * 8

		states[byte] |= (1 <| bit)
	}

	# Summary:
	# Returns whether this layer owns the specified address.
	owns(physical_address: link): bool {
		return not is_available((physical_address as u64) / size)
	}

	# Summary: Adds the specified entry into the available entries
	add(physical_address: link) {
		# Map the slab so that we can write into it
		kernel.mapper.map_page(physical_address, physical_address)

		element = physical_address as PhysicalMemoryManagerAvailableLayerElement
		element.next = none as PhysicalMemoryManagerAvailableLayerElement
		element.previous = last

		# Connect the currently last element to this new element
		if last !== none {
			last.next = element
		}

		# Update the next entry if there is none
		if next === none {
			next = element
		}

		# Update the last entry
		last = element
	}

	# Summary: Removes the specified entry from the available entries
	remove(element: PhysicalMemoryManagerAvailableLayerElement) {
		if element.previous !== none { element.previous.next = element.next }

		if element.next !== none { element.next.previous = element.previous }

		if element === next { next = element.next }

		if element === last { last = element.previous }
	}

	# Summary:
	# Takes the next available entry.
	# Returns the physical address of the taken entry.
	take(): link {
		if next === none return none as PhysicalMemoryManagerAvailableLayerElement

		result = next
		next = result.next
		next.previous = none as PhysicalMemoryManagerAvailableLayerElement

		# Update the last available page to none if we have used all the pages
		if next === none { last = none as link }

		return result
	}

	# Summary:
	# Allocates the next available entry.
	# Returns the physical address of the allocated entry.
	allocate(): link {
		slab = take() as link
		if slab === none return none as link

		index = (slab as u64) / size
		set_unavailable(index)

		return slab
	}

	# Summary: Deallocates the specified entry
	deallocate(physical_address: link): u64 {
		require(((physical_address as u64) & (size - 1)) == 0, 'Address was not aligned correctly')

		index = (physical_address as u64) / size

		# Verify the address is actually allocated and prevent double deallocations as well
		require(not is_available(index), 'Can not deallocate memory that has not been allocated')

		# Set the specified entry available
		set_available(index)

		# Compute the address of the buddy slab.
		# If the just deallocated slab is the left slab, the address should correspond to the right slab.
		# Otherwise, it should correspond to the left slab.
		buddy = (physical_address ¤ size) as PhysicalMemoryManagerAvailableLayerElement

		# If the buddy slab is available as well, we can merge the deallocated slab with its buddy slab.
		if upper !== none and is_available((buddy as u64) / size) {
			remove(buddy)

			left = math.min(physical_address as u64, buddy as u64) as link
			upper.add(left)
		}

		return size
	}
}

PhysicalMemoryManager {
	shared instance: PhysicalMemoryManager

	shared initialize(address: link, memory_information: kernel.SystemMemoryInformation) {
		instance = PhysicalMemoryManager(memory_information) using address
	}

	constant LAYER_COUNT = 8

	constant L0_SIZE = 0x80000
	constant L1_SIZE = 0x40000
	constant L2_SIZE = 0x20000
	constant L3_SIZE = 0x10000
	constant L4_SIZE = 0x8000
	constant L5_SIZE = 0x4000
	constant L6_SIZE = 0x2000
	constant L7_SIZE = 0x1000

	constant L0_COUNT = (kernel.mapper.MAX_MEMORY / L0_SIZE)
	constant L1_COUNT = (kernel.mapper.MAX_MEMORY / L1_SIZE)
	constant L2_COUNT = (kernel.mapper.MAX_MEMORY / L2_SIZE)
	constant L3_COUNT = (kernel.mapper.MAX_MEMORY / L3_SIZE)
	constant L4_COUNT = (kernel.mapper.MAX_MEMORY / L4_SIZE)
	constant L5_COUNT = (kernel.mapper.MAX_MEMORY / L5_SIZE)
	constant L6_COUNT = (kernel.mapper.MAX_MEMORY / L6_SIZE)
	constant L7_COUNT = (kernel.mapper.MAX_MEMORY / L7_SIZE)

	constant LAYER_STATE_MEMORY_SIZE = (L0_COUNT + L1_COUNT + L2_COUNT + L3_COUNT + L4_COUNT + L5_COUNT + L6_COUNT + L7_COUNT) / 8

	layers: PhysicalMemoryManagerLayer[LAYER_COUNT]

	init(memory_information: kernel.SystemMemoryInformation) {
		reserved = memory_information.reserved

		# Setup the layers
		loop (i = 0, i < LAYER_COUNT, i++) {
			layers[i] = this as link + sizeof(PhysicalMemoryManager) + i * sizeof(PhysicalMemoryManagerLayer)
		}

		states = this as link + sizeof(PhysicalMemoryManager) + LAYER_COUNT * sizeof(PhysicalMemoryManagerLayer)
		upper = (this as link + sizeof(PhysicalMemoryManager)) as PhysicalMemoryManagerLayer
		lower = (this as link + sizeof(PhysicalMemoryManager) + sizeof(PhysicalMemoryManagerLayer)) as PhysicalMemoryManagerLayer
		count = L0_COUNT
		size = L0_SIZE

		loop (i = 0, i < LAYER_COUNT, i++) {
			layers[i].depth = i
			layers[i].upper = upper
			layers[i].lower = lower
			layers[i].states = states
			layers[i].size = size

			states += count / 8 # TODO: Can the result be uneven and break things?
			count *= 2
			size /= 2
			upper += sizeof(PhysicalMemoryManagerLayer)
			lower += sizeof(PhysicalMemoryManagerLayer)
		}

		# Fix the first and last layer
		layers[0].upper = none as PhysicalMemoryManagerLayer
		layers[LAYER_COUNT - 1].lower = none as PhysicalMemoryManagerLayer

		# Set all the reserved segments unavailable
		loop (i = 0, i < reserved.size, i++) {
			reserve_region(reserved[i])
		}

		# Compute the number of L0 slabs needed for the whole physical memory
		slabs = memory_information.physical_memory_size / L0_SIZE
		if slabs * L0_SIZE < memory_information.physical_memory_size { slabs++ }

		loop (i = 0, i < slabs, i++) {
			if layers[0].is_available(i) {
				layers[0].add((i * L0_SIZE) as link)
			}
		}

		return
		print(32)

		iterator = layers[0].next

		loop (iterator !== none) {
			debug.write('Available ') debug.write_address(iterator as link) debug.write_line()

			iterator = iterator.next
		}
	}

	print(depth: u8, slab: u64) {
		layer = layers[depth]
		address = slab * layer.size

		if layer.is_available(slab) {
			loop (i = 0, i < (layer.size / L7_SIZE), i++) {
				loop (j = 0, j < LAYER_COUNT - depth - 1, j++) {
					debug.put(` `)
				}

				debug.write(' --- ')
				debug.write_address(address + i * L7_SIZE)
				debug.write_line()
			}

			return
		}

		if layer.is_split((slab * layer.size) as link) {
			print(depth + 1, slab * 2)
			print(depth + 1, slab * 2 + 1)
			return
		}

		loop (i = 0, i < (layer.size / L7_SIZE), i++) {
			loop (j = 0, j < LAYER_COUNT - depth - 1, j++) {
				debug.put(` `)
			}

			debug.write('# --- ')
			debug.write_address(address + i * L7_SIZE)
			debug.write_line()
		}
	}

	print(n: u64) {
		loop (i = 0, i < n, i++) {
			debug.put(`7`)
			debug.put(`6`)
			debug.put(`5`)
			debug.put(`4`)
			debug.put(`3`)
			debug.put(`2`)
			debug.put(`1`)
			debug.put(`0`)
			debug.write(' --- ')
			debug.write_address(i * L0_SIZE)
			debug.write_line()

			print(0, i)
		}
	}

	# Summary:
	# Returns the most suitable layer (index) for the specified amount of bytes.
	layer_index(bytes: u64) {
		if bytes > L0_SIZE panic('No layer can store the specified amount of bytes')
		if bytes > L1_SIZE return 0
		if bytes > L2_SIZE return 1
		if bytes > L3_SIZE return 2
		if bytes > L4_SIZE return 3
		if bytes > L5_SIZE return 4
		if bytes > L6_SIZE return 5
		if bytes > L7_SIZE return 6
		return 7
	}

	# Summary: Reserves the specified region by using L0 slabs
	private reserve_region(segment: Segment) {
		if segment.size > L0_SIZE {
			reserve_region(Segment.new(segment.type, segment.start, segment.start + segment.size / 2))
			reserve_region(Segment.new(segment.type, segment.start + segment.size / 2, segment.end))
			return
		}

		# Find the start and end address of the specified segment so that they are aligned with the layer
		start = segment.start & (-L0_SIZE)
		end = (segment.start + segment.size) & (-L0_SIZE)

		debug.write('Reserving region ')
		debug.write_address(start) debug.put(`-`) debug.write_address(end + L0_SIZE)
		debug.write(' at layer ') debug.write(0)
		debug.write(' (') debug.write(L0_SIZE) debug.write_line(' bytes)')

		# Set both the start and end slab unavailable
		layers[0].set_unavailable((start / L0_SIZE) as u64)
		layers[0].set_unavailable((end / L0_SIZE) as u64)
	}

	# Summary:
	# Reserves the specified memory area.
	reserve(physical_address: link, bytes: u64) {
		layer = layers[layer_index(bytes)]
		start = physical_address & (-layer.size)
		end = (physical_address + bytes) & (-layer.size)

		layers[0].split(start, layer.depth)

		# If the reserved memory area uses two slabs, reserve both
		if end != start {
			layers[0].split(end, layer.depth)
		}
	}

	# Summary:
	# Allocates the specified amount of bytes and maps it to the specified virtual address.
	# Returns the physical address of the allocated memory.
	allocate_unmapped(bytes: u64): link {
		# Find the layer where we want to allocate the specified amount of bytes
		layer = layer_index(bytes)

		# Try allocating the memory directly from chosen layer
		physical_address = layers[layer].allocate()

		if physical_address !== none {
			debug.write('Found available slab ')
			debug.write_address(physical_address as link)
			debug.write(' at layer ')
			debug.write(layer)
			debug.write(' for ')
			debug.write(bytes)
			debug.write_line(' bytes')

			return physical_address
		}

		# If this point is reached, it means we could not find a suitable slab for the specified amount of bytes.
		# We should look for available memory from the upper layers.
		loop (i = layer - 1, i >= 0, i--) {
			# Check if this layer has available memory for us
			if layers[i].next === none continue

			slab = layers[i].take()
			debug.write('Splitting slab ')
			debug.write_address(slab as link)
			debug.write(' at layer ')
			debug.write(i)
			debug.write(' for ')
			debug.write(bytes)
			debug.write_line(' bytes')

			return layers[i].split(slab, layer)
		}

		# If this point is reached, there is no continuous slab available that could hold the specified amount of memory.
		# However, we can still try using multiple slabs to hold specified amount of memory since we are using virtual addresses.
		# In addition, the size of the allocation might be problematic to determine upon deallocation.
		panic('Out of memory')
	}

	# Summary:
	# Allocates the specified amount of bytes and maps it to the same virtual address.
	# Returns the physical address of the allocated memory.
	allocate(bytes: u64): link {
		physical_address = allocate_unmapped(bytes)
		kernel.mapper.map_region(physical_address, physical_address, bytes)

		return physical_address
	}

	# Summary:
	# Allocates the specified amount of bytes and maps it to the specified virtual address.
	# Returns the physical address of the allocated memory.
	allocate(bytes: u64, virtual_address: link): link {
		require((virtual_address & (PAGE_SIZE - 1)) == 0, 'Virtual address was not aligned correctly')

		physical_address = allocate_unmapped(bytes)
		kernel.mapper.map_region(virtual_address, physical_address, bytes)

		return physical_address
	}

	# Summary: Deallocates the specified physical memory.
	deallocate(address: link) {
		require((address & (L7_SIZE - 1)) == 0, 'Physical address was not aligned correctly')

		if layers[7].owns(address) return layers[7].deallocate(address)
		if layers[6].owns(address) return layers[6].deallocate(address)
		if layers[5].owns(address) return layers[5].deallocate(address)
		if layers[4].owns(address) return layers[4].deallocate(address)
		if layers[3].owns(address) return layers[3].deallocate(address)
		if layers[2].owns(address) return layers[2].deallocate(address)
		if layers[1].owns(address) return layers[1].deallocate(address)
		if layers[0].owns(address) return layers[0].deallocate(address)

		panic('Can not deallocate memory that has not been allocated')
	}
}