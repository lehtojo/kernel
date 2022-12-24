namespace kernel

KernelHeap {
	shared initialize() {
		heap.initialize()
	}

	shared allocate(bytes: u64): link {
		require(bytes >= 0, 'Illegal allocation size')

		if bytes <= 16 return heap.s16.allocate()
		if bytes <= 32 return heap.s32.allocate()
		if bytes <= 64 return heap.s64.allocate()
		if bytes <= 128 return heap.s128.allocate()
		if bytes <= 256 return heap.s256.allocate()

		bytes += strideof(u64)
		address = PhysicalMemoryManager.instance.allocate(bytes)
		if address == none panic('Out of memory')

		# Store the size of the allocation at the beginning of the allocated memory
		address.(u64*)[] = bytes
		return address + strideof(u64)
	}

	shared deallocate(address: link): link {
		if heap.s16.deallocate(address) return
		if heap.s32.deallocate(address) return
		if heap.s64.deallocate(address) return
		if heap.s128.deallocate(address) return
		if heap.s256.deallocate(address) return

		# Load the size of the allocation and deallocate the memory
		address -= strideof(u64)
		bytes = address.(u64*)[]
		PhysicalMemoryManager.deallocate(address, bytes)
	}

	shared allocate<T>(): T* {
		return allocate(sizeof(T))
	}
}

namespace heap

constant ESTIMATED_MAX_ALLOCATORS = 100
constant ALLOCATOR_SORT_INTERVAL = 10000

s16: Allocators<SlabAllocator<u8[16]>, u8[16]>
s32: Allocators<SlabAllocator<u8[32]>, u8[32]>
s64: Allocators<SlabAllocator<u8[64]>, u8[64]>
s128: Allocators<SlabAllocator<u8[128]>, u8[128]>
s256: Allocators<SlabAllocator<u8[256]>, u8[256]>

export plain SlabAllocator<T> {
	slabs: u32
	start: link
	end => start + slabs * sizeof(T)

	# Stores the states of all the slabs as bits. This should only be used for debugging.
	states: link

	# Stores the number of times this bucket has been used to allocate. This is used to give buckets a minimum lifetime in order to prevent buckets being created and destroyed immediately
	allocations: u64 = 0

	# Stores the number of used slots in this allocator
	used: u32 = 0

	available: link = none as link
	position: u32 = 0

	init(start: link, slabs: u32) {
		this.start = start
		this.slabs = slabs

		# NOTE: Debug mode only
		this.states = PhysicalMemoryManager.instance.allocate(slabs / 8) # Allocate bits for each slab
	}

	allocate() {
		debug.write('Used slab allocator of ')
		debug.write(sizeof(T))
		debug.write_line(' bytes')

		if available != none {
			result = available

			# NOTE: Debug mode only
			# Set the bit for this slab
			index = (result - start) as u64 / sizeof(T)
			states[index / 8] |= 1 <| (index % 8)

			next = result.(link*)[]
			available = next

			allocations++
			used++

			memory.zero(result, sizeof(T))
			return result
		}

		if position < slabs {
			result = start + position * sizeof(T)

			# NOTE: Debug mode only
			# Set the bit for this slab
			states[position / 8] |= 1 <| (position % 8)

			# Move to the next slab
			position++
			allocations++
			used++

			memory.zero(result, sizeof(T))
			return result
		}

		return none as link
	}

	allocate_slab(index: u64) {
		# Ensure the slab is not already deallocated
		mask = 1 <| (index % 8)
		state = states[index / 8] & mask

		if state == 0 panic('Address already deallocated')

		states[index / 8] ¤= mask
	}

	deallocate(address: link) {
		offset = (address - start) as u64
		index = offset / sizeof(T)
		require(offset - index * sizeof(T) == 0, 'Address did not point to the start of an allocated area')

		# NOTE: Debug mode only
		# Ensure the slab is not already deallocated
		allocate_slab(index)

		address.(link*)[] = available
		available = address

		used--
	}

	dispose() {
		PhysicalMemoryManager.deallocate(start, slabs * sizeof(T))
		PhysicalMemoryManager.deallocate(states, slabs / 8)
	}
}

export plain Allocators<T, S> {
	allocations: u64 = 0
	allocators: T*
	deallocators: T*
	size: u64 = 0
	capacity: u64 = ESTIMATED_MAX_ALLOCATORS
	slabs: u32

	init(slabs: u32) {
		this.allocators = PhysicalMemoryManager.instance.allocate(ESTIMATED_MAX_ALLOCATORS * strideof(T))
		this.deallocators = PhysicalMemoryManager.instance.allocate(ESTIMATED_MAX_ALLOCATORS * strideof(T))
		this.slabs = slabs
	}

	sort_allocators() {
		sort<T>(allocators, size, (a: T, b: T) -> a.used - b.used)
	}

	add() {
		if size >= capacity {
			# Allocate new allocator and deallocator lists
			new_capacity = size * 2
			new_allocators = PhysicalMemoryManager.instance.allocate(new_capacity * strideof(T))
			new_deallocators = PhysicalMemoryManager.instance.allocate(new_capacity * strideof(T))

			# Copy the contents of the old allocator and deallocator lists to the new ones
			memory.copy(new_allocators, allocators, size * strideof(T))
			memory.copy(new_deallocators, deallocators, size * strideof(T))

			# Deallocate the old allocator and deallocator lists
			PhysicalMemoryManager.deallocate(allocators)
			PhysicalMemoryManager.deallocate(deallocators)

			capacity = new_capacity
			allocators = new_allocators
			deallocators = new_deallocators
		}

		# Create a new allocator with its own memory
		states = PhysicalMemoryManager.instance.allocate(slabs * sizeof(S))

		allocator = PhysicalMemoryManager.instance.allocate(sizeof(T)) as T
		allocator.init(states, slabs)

		# Add the new allocator
		allocators[size] = allocator
		deallocators[size] = allocator

		size++
		return allocator
	}

	allocate() {
		# Sort the allocators from time to time
		if (++allocations) % ALLOCATOR_SORT_INTERVAL == 0 sort_allocators()

		loop (i = 0, i < size, i++) {
			allocator = allocators[i]
			result = allocator.allocate()

			if result != none return result
		}

		return add().allocate()
	}

	remove(deallocator: T, i: u64) {
		deallocator.dispose()

		# Remove deallocator from the list
		memory.copy(deallocators + i * strideof(T), deallocators + (i + 1) * strideof(T), (size - i - 1) * strideof(T))
		memory.zero(deallocators + (size - 1) * strideof(T), strideof(T))

		# Find the corresponding allocator from the allocator list linearly, because we can not assume the list is sorted in any way
		loop (j = 0, j < size, j++) {
			if allocators[j] != deallocator continue

			# Remove allocator from the list
			memory.copy(allocators + j * strideof(T), allocators + (j + 1) * strideof(T), (size - j - 1) * strideof(T))
			memory.zero(allocators + (size - 1) * strideof(T), strideof(T))
			stop
		}

		size--
	}

	deallocate(address: link) {
		loop (i = 0, i < size, i++) {
			deallocator = deallocators[i]
			if address < deallocator.start or address >= deallocator.end continue

			deallocator.deallocate(address)

			# Deallocate the allocator if it is empty and is used long enough
			if deallocator.allocations > slabs / 2 and deallocator.used == 0 {
				remove(deallocator, i)
			}

			return true
		}

		return false
	}
}

initialize() {
	s16 = PhysicalMemoryManager.instance.allocate(sizeof(Allocators<SlabAllocator<u8[16]>, u8[16]>)) as Allocators<SlabAllocator<u8[16]>, u8[16]>
	s32 = PhysicalMemoryManager.instance.allocate(sizeof(Allocators<SlabAllocator<u8[32]>, u8[32]>)) as Allocators<SlabAllocator<u8[32]>, u8[32]>
	s64 = PhysicalMemoryManager.instance.allocate(sizeof(Allocators<SlabAllocator<u8[64]>, u8[64]>)) as Allocators<SlabAllocator<u8[64]>, u8[64]>
	s128 = PhysicalMemoryManager.instance.allocate(sizeof(Allocators<SlabAllocator<u8[128]>, u8[128]>)) as Allocators<SlabAllocator<u8[128]>, u8[128]>
	s256 = PhysicalMemoryManager.instance.allocate(sizeof(Allocators<SlabAllocator<u8[256]>, u8[256]>)) as Allocators<SlabAllocator<u8[256]>, u8[256]>

	s16.init(PhysicalMemoryManager.L0_SIZE / 16)
	s32.init(PhysicalMemoryManager.L0_SIZE / 32)
	s64.init(PhysicalMemoryManager.L0_SIZE / 64)
	s128.init(PhysicalMemoryManager.L0_SIZE / 128)
	s256.init(PhysicalMemoryManager.L0_SIZE / 256)
}
