namespace kernel

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
	# In manual mode, this function just sets the bits correctly and does not add or remove slabs from lists.
	split(physical_address: link, to: u32, manual: bool, allocate: bool): link {
		slab: link = ((physical_address as u64) & (-size)) as link

		# Stop when the target depth is reached
		if depth == to {
			index = (slab as u64) / size

			# Allocate or deallocate the final slab depending on the arguments
			if allocate { set_unavailable(index) }
			else not manual { add(slab) }

			return slab
		}

		if is_split(slab) {
			# Since the slab on the current layer is already split, continue lower
			return lower.split(physical_address, to)
		}

		index = (slab as u64) / size
		require(is_available(index), 'Can not split an unavailable slab')

		# Since we are splitting the specified slab, it must be set unavailable
		if not manual remove(slab as PhysicalMemoryManagerAvailableLayerElement)
		set_unavailable(index)

		# Compute the addresses of the two lower layer slabs
		slab = physical_address & (-lower.size)
		buddy = ((slab as u64) ¤ lower.size) as link

		# Set the buddy slab available on the lower layer
		if not manual lower.add(buddy)

		# Since we have not reached the target depth, continue lower
		return lower.split(physical_address, to)
	}

	# Summary:
	# Splits slabs towards the specified physical address down to the specified depth.
	# Allocates the lowest slab containing the specified physical address.
	split(physical_address: link, to: u32): link {
		return split(physical_address, to, false, true)
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
		element = physical_address as PhysicalMemoryManagerAvailableLayerElement

		# Use quick mapping in order to write to the physical address
		mapped_element = kernel.mapper.quickmap<PhysicalMemoryManagerAvailableLayerElement>(physical_address)
		mapped_element.next = none as PhysicalMemoryManagerAvailableLayerElement
		mapped_element.previous = last

		# Connect the currently last element to this new element
		if last !== none {
			kernel.mapper.quickmap<PhysicalMemoryManagerAvailableLayerElement>(last as link).next = element
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
		mapped_element = kernel.mapper.quickmap<PhysicalMemoryManagerAvailableLayerElement>(element as link)
		element_previous = mapped_element.previous
		element_next = mapped_element.next

		# Update the previous entry of the specified element
		if element_previous !== none {
			kernel.mapper.quickmap<PhysicalMemoryManagerAvailableLayerElement>(element_previous as link).next = element_next
		}

		# Update the next entry of the specified element
		if element_next !== none {
			kernel.mapper.quickmap<PhysicalMemoryManagerAvailableLayerElement>(element_next as link).previous = element_previous
		}

		if element === next { next = element_next }
		if element === last { last = element_previous }
	}

	# Summary:
	# Takes the next available entry.
	# Returns the physical address of the taken entry.
	take(): link {
		if next === none return none as link

		result = next as link

		# Load the available element from the element we take
		next = kernel.mapper.quickmap<PhysicalMemoryManagerAvailableLayerElement>(result as link).next

		# Update the next element to be the first available element by settings its previous element to none
		if next !== none {
			kernel.mapper.quickmap<PhysicalMemoryManagerAvailableLayerElement>(next as link).previous = none as PhysicalMemoryManagerAvailableLayerElement
		} else {
			# Update the last available page to none if we have used all the pages
			last = none as PhysicalMemoryManagerAvailableLayerElement
		}

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

	unsplit(physical_address: link, add: bool) {
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
			# Remove the buddy slab from the available slabs
			remove(buddy)

			# Find out the left slab
			left = math.min(physical_address as u64, buddy as u64) as link

			# Deallocate the upper slab, because the lower two are now available and merged
			debug.write('Merging into upper slab ') debug.write_address(left) debug.write(' at layer ') debug.write_line(upper.depth)
			upper.unsplit(left, add)

		} else {
			# Since we can not merge, add this slab to the available list
			if add { add(physical_address) }
		}
	}

	# Summary: Deallocates the specified entry
	deallocate(physical_address: link, add: bool): u64 {
		unsplit(physical_address, add)
		return size
	}
}

PhysicalMemoryManager {
	shared instance: PhysicalMemoryManager

	shared initialize(memory_information: kernel.SystemMemoryInformation) {
		instance = PhysicalMemoryManager(memory_information) using memory_information.physical_memory_manager_virtual_address
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
			layers[i] = (this as link + sizeof(PhysicalMemoryManager) + i * sizeof(PhysicalMemoryManagerLayer)) as PhysicalMemoryManagerLayer
		}

		states = this as link + sizeof(PhysicalMemoryManager) + LAYER_COUNT * sizeof(PhysicalMemoryManagerLayer)
		upper = (this as link + sizeof(PhysicalMemoryManager) - sizeof(PhysicalMemoryManagerLayer)) as PhysicalMemoryManagerLayer
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
			reserve_region_with_largest_slabs(reserved[i])
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
		#print(32)

		iterator = layers[0].next

		loop (iterator !== none) {
			debug.write('Available ') debug.write_address(iterator as link) debug.write_line()

			iterator = kernel.mapper.quickmap<PhysicalMemoryManagerAvailableLayerElement>(iterator as link).next
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
	layer_index(bytes: u64): u64 {
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
	private reserve_region_with_largest_slabs(segment: Segment) {
		if segment.size > L0_SIZE {
			reserve_region_with_largest_slabs(Segment.new(segment.type, segment.start, segment.start + segment.size / 2))
			reserve_region_with_largest_slabs(Segment.new(segment.type, segment.start + segment.size / 2, segment.end))
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
	# Reserves the specified slab
	reserve_slab(slab: Segment): _ {
		# Find the layer that has the specified slab
		layer = layers[layer_index(slab.size)]
		start = slab.start & (-layer.size)

		# Split the layers above the slab so that it can be reserved
		# Note: Splitting here also reserves the slab
		layers[0].split(start, layer.depth)
	}

	# Summary:
	# Allocates the specified amount of bytes and returns its physical address.
	allocate_physical_region(bytes: u64): link {
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
	# Allocates the specified amount of bytes and maps it to kernel space.
	# Returns the virtual address of the allocated memory.
	allocate(bytes: u64): link {
		physical_address = allocate_physical_region(bytes)

		return kernel.mapper.map_kernel_region(physical_address, bytes)
	}

	# Summary:
	# Deallocates the slab that starts the specified physical address.
	# Use deallocation, which allows for fragmentation when, for example, you deallocate a region in the middle of an allocation.
	# Parameter "add" controls whether the deallocated region is added to available memory.
	deallocate_all(address: link, add: bool): u64 {
		require((address & (L7_SIZE - 1)) == 0, 'Physical address was not aligned correctly')

		if layers[7].owns(address) return layers[7].deallocate(address, add)
		if layers[6].owns(address) return layers[6].deallocate(address, add)
		if layers[5].owns(address) return layers[5].deallocate(address, add)
		if layers[4].owns(address) return layers[4].deallocate(address, add)
		if layers[3].owns(address) return layers[3].deallocate(address, add)
		if layers[2].owns(address) return layers[2].deallocate(address, add)
		if layers[1].owns(address) return layers[1].deallocate(address, add)
		if layers[0].owns(address) return layers[0].deallocate(address, add)

		panic('Can not deallocate memory that has not been allocated')
	}

	# Summary:
	# Deallocates the slab that starts the specified physical address.
	# Use deallocation, which allows for fragmentation when, for example, you deallocate a region in the middle of an allocation.
	deallocate_all(address: link): u64 {
		return deallocate_all(address, true)
	}

	# Summary:
	# Iterates through the specified region with largest possible slabs inside it and calls the specified action with them.
	private shared iterate_region_with_largest_slabs<T>(region: Segment, data: T, action: (Segment, T) -> _): _ {
		require(memory.is_aligned(region.start, L0_SIZE), 'Start of the specified region was not aligned')
		require(memory.is_aligned(region.size, L0_SIZE), 'Size of the specified region was not aligned')

		position = region.start

		loop (position < region.end) {
			# Find the largest slab that starts at the current position and fits in the remaining region
			i = LAYER_COUNT - 1

			loop (i >= 0, i--) {
				layer = layers[i]

				# Move to a smaller slab if the position is not a start of a slab on this layer
				if not memory.is_aligned(position, layer.size) continue

				# Ensure the slab that starts at the current position is inside the remaining region
				end = position + layer.size # Todo: Overflow might be possible
				if end <= region.end continue

				# We found the next largest slab inside the remaining region, give it to the caller
				action(data, Segment.new(position, position + layer.size))

				# Move past the consumed slab
				position += layer.size
				stop
			}

			if i < 0 panic('Failed to iterate the region')
		}
	}

	# Summary:
	# Deallocates the specified physical region while allowing fragmentation.
	# Fragmentation means that part of a large slab can be deallocated.
	# In this case, the remaining regions remain allocated with the help of smaller slabs.
	deallocate_fragment(physical_region: Segment): _ {
		# Verify the specified physical region is valid
		require(memory.is_aligned(physical_region.start, L7_SIZE), 'Physical memory region was not aligned')
		require(memory.is_aligned(physical_region.size, L7_SIZE), 'Physical memory region size was not aligned')

		# Find the layer with the smallest slab that owns the specified physical region
		layer = none as PhysicalMemoryManagerLayer
		containing_slab = Segment.empty()
		i = LAYER_COUNT - 1

		loop (i >= 0, i--) {
			layer = layers[i]
			
			# Find the start of the slab that contains the specified region on this layer
			containing_slab_start = physical_region.size & (-layer.size)
			containing_slab_end = containing_slab_start + layer.size
			containing_slab = Segment.new(containing_slab_start, containing_slab_end)

			# Stop if this layer owns the physical region			
			if layer.owns(containing_slab_start) stop
		}

		# Panic if the physical region is not even allocated
		if i < 0 panic('Specified physical region was not allocated')

		# Deallocate the slab that contains the physical region and do not add it back to available slabs
		deallocate(start, false)

		# Reserve the regions inside the deallocated slab that are not being deallocated
		remaining_left_region = Segment.new(containing_slab.start, physical_region.start)
		remaining_right_region = Segment.new(physical_region.end, containing_slab.end)

		# Iterate all slabs inside the left and right remaining region and reserve them, because they are not being deallocated
		iterate_region_with_largest_slabs<PhysicalMemoryManager>(remaining_left_region, this, (slab: Segment, manager: PhysicalMemoryManager) -> manager.reserve_slab(slab))
		iterate_region_with_largest_slabs<PhysicalMemoryManager>(remaining_right_region, this, (slab: Segment, manager: PhysicalMemoryManager) -> manager.reserve_slab(slab))

		# Deallocate all slabs inside the deallocated region
		iterate_region_with_largest_slabs<PhysicalMemoryManager>(physical_region, this, (slab: Segment, manager: PhysicalMemoryManager) -> manager.deallocate(slab))
	}
}