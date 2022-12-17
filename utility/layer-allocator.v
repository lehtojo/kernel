LayerAvailableElement {
	next: LayerAvailableElement
	previous: LayerAvailableElement
}

pack Layer {
	depth: u32
	upper: Layer*
	lower: Layer*

	states: link
	size: u64

	next: LayerAvailableElement
	last: LayerAvailableElement

	# Summary:
	# Splits slabs towards the specified physical address down to the specified depth.
	# Allocates the lowest slab containing the specified physical address.
	split(physical_address: link, to: u32): link {
		# Stop when the target depth is reached
		if depth == to {
			index = (slab as u64) / size
			set_unavailable(index)
			return slab
		}

		slab: link = (physical_address as u64) & (!(size - 1))

		if is_split(slab) {
			# Since the slab on the current layer is already split, continue lower
			return lower[].split(physical_address, to)
		}

		index = (slab as u64) / size
		require(is_available(index), 'Can not split an unavailable slab')

		# Since we are splitting the specified slab, it must be set unavailable
		remove(slab as LayerAvailableElement)
		set_unavailable(index)

		# Compute the addresses of the two lower layer slabs
		slab = physical_address & (!(lower[].size - 1))
		buddy = ((slab as u64) ¤ lower[].size) as link

		# Set the buddy slab available on the lower layer
		lower[].add(buddy)

		# Since we have not reached the target depth, continue lower
		return lower[].split(physical_address, to)
	}

	# Summary:
	# Splits slabs towards the specified physical address down to the specified depth.
	# Allocates the lowest slab containing the specified physical address.
	split_without_adding_available_slabs(physical_address: link, to: u32): link {
		# Stop when the target depth is reached
		if depth == to {
			index = (slab as u64) / size
			set_unavailable(index)
			return slab
		}

		slab: link = (physical_address as u64) & (!(size - 1))

		if is_split(slab) {
			# Since the slab on the current layer is already split, continue lower
			return lower[].split_without_adding_available_slabs(physical_address, to)
		}

		index = (slab as u64) / size
		require(is_available(index), 'Can not split an unavailable slab')

		# Since we are splitting the specified slab, it must be set unavailable
		set_unavailable(index)

		# Since we have not reached the target depth, continue lower
		return lower[].split_without_adding_available_slabs(physical_address, to)
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

		return not lower[].is_available(left) or not lower[].is_available(right)
	}

	# Summary:
	# Adds all available slabs to available entries
	add_available_slabs(slab: link) {
		if is_available((slab as u64) / size) {
			add(slab)
		}

		if not is_split(slab) return

		lower[].add_available_slabs(slab)
		lower[].add_available_slabs(slab + lower[].size)
	}

	# Summary: Returns whether the specified entry is available
	is_available(index: u64): bool {
		byte = index / 8
		bit = index - byte * 8

		return (states[byte] |> bit) & 1
	}

	# Summary: Sets the specified entry available
	set_available(index: u64) {
		byte = index / 8
		bit = index - byte * 8

		states[byte] |= (1 <| bit)
	}

	# Summary: Sets the specified entry unavailable
	set_unavailable(index: u64) {
		byte = index / 8
		bit = index - byte * 8

		states[byte] &= (!(1 <| bit))
	}

	# Summary:
	# Returns whether this layer owns the specified address.
	owns(physical_address: link): bool {
		return not is_available((physical_address as u64) / size)
	}

	# Summary: Adds the specified entry into the available entries
	add(physical_address: link) {
		element = physical_address as LayerAvailableElement
		element.next = none as LayerAvailableElement
		element.previous = last

		# Connect the currently last element to this new element
		last.next = element

		# Update the last entry
		last = element
	}

	# Summary: Removes the specified entry from the available entries
	remove(element: LayerAvailableElement) {
		if element.previous !== none { element.previous.next = element.next }

		if element.next !== none { element.next.previous = element.previous }

		if element === next { next = element.next }

		if element === last { last = element.previous }
	}

	# Summary:
	# Takes the next available entry.
	# Returns the physical address of the taken entry.
	take(): link {
		if next === none return none as LayerAvailableElement

		result = next
		next = result.next
		next.previous = none as LayerAvailableElement

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
		buddy = (physical_address ¤ size) as LayerAvailableElement

		# If the buddy slab is available as well, we can merge the deallocated slab with its buddy slab.
		if upper !== none and is_available((buddy as u64) / size) {
			remove(buddy)

			left = math.min(physical_address, buddy)
			upper.add(left)
		}

		return size
	}
}

LayerAllocator {
	shared instance: LayerAllocator

	shared initialize(reservations: List<Segment>) {
		instance = LayerAllocator(reservations) using 0x200000
	}

	constant MAX_MEMORY = 512000000000 # 512 GB
	constant LAYER_COUNT = 8

	constant L0_SIZE = 0x800000
	constant L1_SIZE = 0x400000
	constant L2_SIZE = 0x200000
	constant L3_SIZE = 0x100000
	constant L4_SIZE = 0x80000
	constant L5_SIZE = 0x40000
	constant L6_SIZE = 0x20000
	constant L7_SIZE = 0x10000

	constant L0_COUNT = (MAX_MEMORY / L0_SIZE)
	constant L1_COUNT = (MAX_MEMORY / L1_SIZE)
	constant L2_COUNT = (MAX_MEMORY / L2_SIZE)
	constant L3_COUNT = (MAX_MEMORY / L3_SIZE)
	constant L4_COUNT = (MAX_MEMORY / L4_SIZE)
	constant L5_COUNT = (MAX_MEMORY / L5_SIZE)
	constant L6_COUNT = (MAX_MEMORY / L6_SIZE)
	constant L7_COUNT = (MAX_MEMORY / L7_SIZE)

	constant LAYER_STATE_MEMORY_SIZE = (L0_COUNT + L1_COUNT + L2_COUNT + L3_COUNT + L4_COUNT + L5_COUNT + L6_COUNT + L7_COUNT) / 4

	layers: Layer[LAYER_COUNT]

	init(reservations: List<Segment>) {
		extent = 0

		states = this as link + capacityof(LayerAllocator)
		upper = layers as Layer*
		lower = layers as Layer* + capacityof(Layer)
		count = L0_COUNT
		size = L0_SIZE

		loop (i = 0, i < LAYER_COUNT, i++) {
			layers[i].depth = i
			layers[i].upper = upper
			layers[i].lower = lower
			layers[i].states = states
			layers[i].size = size

			states += count / 8
			count *= 2
			size /= 2
			upper += capacityof(Layer)
			lower += capacityof(Layer)
		}

		# Fix the first and last layer
		layers[0].upper = none as Layer*
		layers[LAYER_COUNT - 1].lower = none as Layer*

		# Set all the reserved segments unavailable
		loop (i = 0, i < reservations.size, i++) {
			reserve_without_adding_available_slabs(reservations[i])
		}

		# TODO: Generate the correct number of L0 entries here
		# TODO: Use lazy generation?
		loop (i = 0, i < 10, i++) {
			address = (i * L0_SIZE) as link
			layers[0].add(address)
			layers[0].add_available_slabs(address)
		}
	}

	# Summary:
	# Returns the most suitable layer (index) for the specified amount of bytes.
	layer_index(bytes: u64) {
		if bytes > L0_SIZE {
			panic('Too large allocation (unsupported)')
		}

		if bytes > L1_SIZE return 0
		if bytes > L2_SIZE return 1
		if bytes > L3_SIZE return 2
		if bytes > L4_SIZE return 3
		if bytes > L5_SIZE return 4
		if bytes > L6_SIZE return 5
		if bytes > L7_SIZE return 6

		return 7
	}

	private reserve_without_adding_available_slabs(segment: Segment) {
		bytes = (segment.end - segment.start) as u64
		layer = layers[layer_index(bytes)]
		start = segment.start & (!(layer.size - 1))
		end = (segment.start + bytes) & (!(layer.size - 1))

		layers[0].split_without_adding_available_slabs(start, layer.depth)

		# If the reserved memory area uses two slabs, reserve both
		if end != start {
			layers[0].split_without_adding_available_slabs(end, layer.depth)
		}
	}

	# Summary:
	# Reserves the specified memory area.
	reserve(physical_address: link, bytes: u64) {
		layer = layers[layer_index(bytes)]
		start = physical_address & (!(layer.size - 1))
		end = (physical_address + bytes) & (!(layer.size - 1))

		layers[0].split(start, layer.depth)

		# If the reserved memory area uses two slabs, reserve both
		if end != start {
			layers[0].split(end, layer.depth)
		}
	}

	# Summary:
	# Allocates the specified amount of bytes and maps it to the specified virtual address.
	# Returns the physical address of the allocated memory.
	allocate(bytes: u64, virtual_address: link): link {
		require(((virtual_address as u64) & (L7_SIZE - 1)) == 0, 'Virtual address was not aligned correctly')

		# Find the layer where we want to allocate the specified amount of bytes
		layer = layer_index(bytes)

		# Try allocating the memory directly from chosen layer
		physical_address = layers[layer].allocate()
		if physical_address !== none return physical_address

		# If this point is reached, it means we could not find a suitable slab for the specified amount of bytes.
		# We should look for available memory from the upper layers.
		loop (i = layer - 1, i >= 0, i--) {
			# Check if this layer has available memory for us
			if layers[i].next === none continue

			slab = layers[i].take()
			return layers[i].split(slab, layer)
		}

		# If this point is reached, there is no continuous slab available that could hold the specified amount of memory.
		# However, we can still try using multiple slabs to hold specified amount of memory since we are using virtual addresses.
		panic('TODO: Fragmented allocation')
	}

	# Summary: Deallocates the specified memory.
	deallocate(address: link) {
		require(((address as u64) & (L7_SIZE - 1)) == 0, 'Physical address was not aligned correctly')

		if layers[7].owns(address) return layers[7].deallocate(virtual_address)
		if layers[6].owns(address) return layers[6].deallocate(virtual_address)
		if layers[5].owns(address) return layers[5].deallocate(virtual_address)
		if layers[4].owns(address) return layers[4].deallocate(virtual_address)
		if layers[3].owns(address) return layers[3].deallocate(virtual_address)
		if layers[2].owns(address) return layers[2].deallocate(virtual_address)
		if layers[1].owns(address) return layers[1].deallocate(virtual_address)
		if layers[0].owns(address) return layers[0].deallocate(virtual_address)

		panic('Can not deallocate memory that has not been allocated')
	}

	# Summary: Deallocates the specified memory and unmaps it from the specified virtual address.
	deallocate(address: link, virtual_address: link) {

	}
}