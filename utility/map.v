constant MIN_MAP_CAPACITY = 5
constant REMOVED_SLOT_MARKER = -2

export pack MapSlot<K, V> {
	key: K
	value: V
	next: i32 
	previous: i32 
}

export plain Map<K, V> {
	private allocator: Allocator
	private first: i64 = -1 # Zero-based index of first slot
	private last: i64 = -1 # Zero-based index of last slot
	private slots: MapSlot<K, V>* = none as MapSlot<K, V>*
	private capacity: i64 = 1
	private removed: i32 = 0 # Number of removed slots

	readable size: i64 = 0

	init(allocator: Allocator) {
		this.allocator = allocator
	}

	init(capacity: i64) {
		this.allocator = allocator
		rehash(capacity)
	}

	# Summary: Resizes the internal container to the specified size and inserts all elements back
	rehash(to: i64): _ {
		if to < MIN_MAP_CAPACITY { to = MIN_MAP_CAPACITY }

		# Save the old slots for iteration
		previous_slots = slots

		# Start from the first slot
		index = first

		# Allocate the new slots
		slots = allocator.allocate(to * strideof(MapSlot<K, V>))
		memory.zero(slots, to * strideof(MapSlot<K, V>))
		capacity = to
		first = -1
		last = -1
		size = 0
		removed = 0

		if previous_slots === none return

		loop (index >= 0) {
			slot = previous_slots[index]
			add(slot.key, slot.value) # Add the slot to the new slots

			index = slot.next - 1 # Indices are 1-based
		}

		allocator.deallocate(previous_slots)
	}

	# Summary: Adds the value with the specified key into this map 
	add(key: K, value: V): _ {
		# If the load factor will exceed 50%, rehash the map now
		load_factor = (size + removed + 1) as decimal / capacity

		if load_factor > 0.5 {
			rehash(capacity * 2)
		}

		hash = key as i64 
		if compiles { key.hash() } { hash = key.hash() }

		attempt = 0

		# Find an available slot by quadratic probing
		loop {
			index = 0
			if attempt < 10 { index = (hash + attempt * attempt) as u64 % capacity }
			else { index = (hash + attempt) as u64 % capacity }

			slot = slots[index]

			# Process occupied slots separately
			if slot.next > 0 or slot.next == -1 {
				# If the slot has the same key, replace the value
				if slot.key == key {
					slot.value = value
					slots[index] = slot
					return
				}

				attempt++
				continue
			}

			# If we allocate a removed slot, decrement the removed count
			if slot.next == REMOVED_SLOT_MARKER {
				removed--
			}

			# Allocate the slot for the specified key and value
			slot.key = key
			slot.value = value
			slot.next = -1
			slot.previous = -1

			if last >= 0 {
				# Connect the last slot to the new slot
				previous = slots[last]
				previous.next = index + 1
				slots[last] = previous

				# Connect the new slot to the last slot
				slot.previous = last + 1

				# Update the index of the last added slot
				last = index
			}

			# If this is the first slot to be added, update the index of the first and the last slot
			if first < 0 {
				first = index
				last = index
			}

			slots[index] = slot
			size++
			return
		}
	}

	# Summary: Adds the value with the specified key into this map if the key does not exist in this map
	try_add(key: K, value: V): bool {
		if contains_key(key) return false
		add(key, value)
		return true
	}

	# Summary: Removes the value associated with the specified key
	remove(key: K): _ {
		# Just return if the map is empty, this also protects from the situation where the map is not allocated yet
		if size == 0 return

		hash = key as i64 
		if compiles { key.hash() } { hash = key.hash() }

		attempt = 0

		# Find the slot by quadratic probing
		loop {
			index = 0
			if attempt < 10 { index = (hash + attempt * attempt) as u64 % capacity }
			else { index = (hash + attempt) as u64 % capacity }

			attempt++

			slot = slots[index]

			# Stop if we found an empty slot
			if slot.next == 0 return

			# Continue if we found a removed slot
			if slot.next == REMOVED_SLOT_MARKER continue

			# If the slot has the same key, remove it
			if slot.key == key {
				# If the slot is the first one, update the index of the first slot
				if index == first {
					first = slot.next - 1
				}

				# If the slot is the last one, update the index of the last slot
				if index == last {
					last = slot.previous - 1
				}

				# If the slot has a previous slot, connect it to the next slot
				if slot.previous > 0 {
					previous = slots[slot.previous - 1]
					previous.next = slot.next
					slots[slot.previous - 1] = previous
				}

				# If the slot has a next slot, connect it to the previous slot
				if slot.next > 0 {
					next = slots[slot.next - 1]
					next.previous = slot.previous
					slots[slot.next - 1] = next
				}

				# Update the size of the map
				size--

				# Update the number of removed slots
				# NOTE: Removed slots still slow down finding other slots and thus are taken into account in the load factor
				removed++

				# Free the slot
				slot.key = none as K
				slot.value = none as V
				slot.next = REMOVED_SLOT_MARKER
				slot.previous = REMOVED_SLOT_MARKER
				slots[index] = slot

				return
			}
		}
	}

	# Summary:
	# Returns the index of the slot that has the specified key.
	# If the key does not exist in this map, this function returns -1.
	try_find(key: K): i64 {
		# Just return -1 if the map is empty, this also protects from the situation where the map is not allocated yet
		if size == 0 return -1

		hash = key as i64 
		if compiles { key.hash() } { hash = key.hash() }

		attempt = 0

		# Find the slot by quadratic probing
		loop {
			index = 0
			if attempt < 10 { index = (hash + attempt * attempt) as u64 % capacity }
			else { index = (hash + attempt) as u64 % capacity }

			attempt++

			slot = slots[index]

			# Stop if we found an empty slot
			if slot.next == 0 return -1

			# Continue if we found a removed slot
			if slot.next == REMOVED_SLOT_MARKER continue

			# If the slot has the same key, return the value
			if slot.key == key return index
		}
	}

	# Summary: Returns whether a value exists in this map with the specified key
	contains_key(key: K): bool {
		return try_find(key) >= 0
	}

	# Summary: Returns the value associated with the specified key
	get(key: K): V {
		index = try_find(key)
		if index < 0 panic('Map did not contain the specified key')

		return slots[index].value
	}

	# Summary: Attemps to return the value associated with the specified key
	try_get(key: K): Optional<V> {
		index = try_find(key)
		if index < 0 return Optionals.empty<V>()

		return Optionals.new<V>(slots[index].value)
	}

	# Summary: Adds or updates the value associated with the key
	set(key: K, value: V): _ {
		add(key, value)
	}

	# Summary: Returns the keys associated with the values into the specified list
	get_keys(keys: List<K>): _ {
		index = first

		loop (index >= 0) {
			slot = slots[index]
			keys.add(slot.key)

			index = slot.next - 1
		}
	}

	# Summary: Returns the values associated with the keys into the specified list
	get_values(values: List<V>): _ {
		index = first

		loop (index >= 0) {
			slot = slots[index]
			values.add(slot.value)

			index = slot.next - 1
		}
	}

	# Summary: Removes all values from this map
	clear(): _ {
		if slots !== none {
			allocator.deallocate(slots)
		}

		first = -1
		last = -1
		slots = none as MapSlot<K, V>*
		capacity = 1
		size = 0
		removed = 0
	}

	# Summary: Destructs this object
	destruct(): _ {
		clear()
		allocator.deallocate(this as link)
	}
}