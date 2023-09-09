namespace kernel.system_calls

constant FUTEX_OPERATION_WAIT = 0
constant FUTEX_OPERATION_WAKE = 1
constant FUTEX_OPERATION_WAIT_BITSET = 9
constant FUTEX_OPERATION_WAKE_BITSET = 10

constant FUTEX_OPERATION_FLAG_PRIVATE = 128
constant FUTEX_OPERATION_FLAG_CLOCK_REALTIME = 256

constant FUTEX_KEY_FLAG_PRIVATE = 1

constant FUTEX_BITSET_MATCH_ANY = 0xffffffff

constant FUTEX_KEY_FLAG_MASK = 0b11
constant FUTEX_KEY_ADDRESS_MASK = !FUTEX_KEY_FLAG_MASK

pack FutexKey {
	value: u64

	address => (value & FUTEX_KEY_ADDRESS_MASK) as u32*
	flags => value & FUTEX_KEY_FLAG_MASK

	shared new(address: u64, flags: u8): FutexKey {
		return pack { value: address | flags } as FutexKey
	}

	hash(): u64 {
		return value
	}
}

pack FutexQueueElement {
	process: Process
	operation: i32
	value: u32

	bitset => value

	shared new(process: Process, operation: i32, value: u32): FutexQueueElement {
		return pack { process: process, operation: operation, value: value } as FutexQueueElement
	}
}

namespace Futexes {
	private allocator: Allocator
	private _queues: Map<FutexKey, List<FutexQueueElement>>

	get_queues(): Map<FutexKey, List<FutexQueueElement>> {
		if _queues === none {
			allocator = HeapAllocator.instance
			_queues = Map<FutexKey, List<FutexQueueElement>>(HeapAllocator.instance) using KernelHeap
		}

		return _queues
	}

	has_queue(key: FutexKey): bool {
		queues = get_queues()
		return queues.contains_key(key)
	}

	get_queue(key: FutexKey): List<FutexQueueElement> {
		queues = get_queues()

		if not queues.contains_key(key) {
			queue = List<FutexQueueElement>(HeapAllocator.instance) using allocator
			queues.add(key, queue)
		}

		return queues[key]
	}

	key(address: u64): Result<FutexKey, i64> {
		process = get_process()

		# Verify the specified address is aligned to 4 bytes
		if not memory.is_aligned(address, 4) return EINVAL

		# Verify we have read access to the specified address
		if not is_valid_region(process, address as link, 4, false) return EFAULT

		return FutexKey.new(address, FUTEX_KEY_FLAG_PRIVATE)
	}

	wait_bitset(key: FutexKey, operation: i32, bitset: u32): i64 {
		process = get_process()
		debug.write('Futexes: Thread ') debug.write(process.tid) debug.write(' waits with bitset ')
		debug.write_address(bitset) debug.write_line()

		queue = get_queue(key)
		queue.add(FutexQueueElement.new(process, operation, bitset))
		return 0
	}

	wait_normal(key: FutexKey, operation: u32): i64 {
		process = get_process()
		debug.write('Futexes: Thread ') debug.write(process.tid) debug.write_line(' waits')

		queue = get_queue(key)
		queue.add(FutexQueueElement.new(process, operation, 0))
		return 0
	}

	wait(key: FutexKey, operation: u32, value_1: u32, value_2: u32, value_3: u32): i64 {
		expected_value = value_1
		actual_value = key.address[]

		if expected_value != actual_value {
			debug.write_line('Futexes: Address did not contain the expected value')
			return EAGAIN
		}

		result = when (operation) {
			FUTEX_OPERATION_WAIT => wait_normal(key, operation),
			FUTEX_OPERATION_WAIT_BITSET => wait_bitset(key, operation, value_3),
			else => {
				debug.write_line('Futexes: Unsupported waiting operation')
				EINVAL
			}
		}

		if result != 0 return result

		# Block the thread until the futex wake operation
		process = get_process()

		process.block(
			FutexBlocker.try_create(HeapAllocator.instance).then((blocker: Blocker) -> {
				blocker.set_system_call_result(0)
				return true
			})
		)

		return 0
	}

	try_wake_bitset(element: FutexQueueElement, bitset: u32): bool {
		if bitset != FUTEX_BITSET_MATCH_ANY and (element.bitset & bitset) == 0 {
			debug.write_line('Futexes: Mismatching bitsets, not waking up')
			return false
		}

		debug.write_line('Futexes: Waking up...')
		element.process.unblock()
		return true
	}

	try_wake_normal(element: FutexQueueElement): bool {
		debug.write_line('Futexes: Waking up...')
		element.process.unblock()
		return true
	}

	try_wake(element: FutexQueueElement, operation: u32, bitset: u32): bool {
		return when (operation) {
			FUTEX_OPERATION_WAKE => try_wake_normal(element),
			FUTEX_OPERATION_WAKE_BITSET => try_wake_bitset(element, bitset),
			else => {
				panic('Futexes: Unsupported operation')
				false
			}
		}
	}

	wake(key: FutexKey, operation: u32, wake_limit: u64, bitset: u32): i64 {
		# If the corresponding queue does not exist, no waiter will be waken up
		if not has_queue(key) {
			debug.write_line('Futexes: No waiters found with the specified key')
			return 0
		}

		queue = get_queue(key)
		queue_index = 0
		wake_count = 0

		loop (wake_count < wake_limit) {
			# Verify we have not reached the end
			if queue_index >= queue.size {
				debug.write_line('Futexes: No more waiters to wake up')
				stop
			}

			element = queue[queue_index]

			if not try_wake(element, operation, bitset) {
				queue_index++
				continue
			}

			# Because we have woken up the waiter, remove it and increment wake count
			queue.remove_at(queue_index)
			wake_count++
		}

		return wake_count
	}

	wake(address: u64): i64 {
		key_or_error = Futexes.key(address as u64)

		if key_or_error has not key {
			debug.write_line('Futexes: Failed to get the futex key')
			return key_or_error.error
		}

		return Futexes.wake(key, FUTEX_OPERATION_WAKE, 0xffffffff, FUTEX_BITSET_MATCH_ANY)
	}
}

# System call: futex
export system_futex(
	userspace_address_1: u32*,
	operation_and_flags: i32,
	value_1: u32,
	value_2: u64,
	userspace_address_2: u32*,
	value_3: u32
): i64 {
	debug.write('System call: futex: ')
	debug.write('userspace_address_1=') debug.write_address(userspace_address_1)
	debug.write(', operation_and_flags=') debug.write(operation_and_flags)
	debug.write(', value_1=') debug.write(value_1)
	debug.write(', value_2=') debug.write(value_2)
	debug.write(', userspace_address_2=') debug.write_address(userspace_address_2)
	debug.write(', value_3=') debug.write(value_3)
	debug.write_line()	

	key_or_error = Futexes.key(userspace_address_1 as u64)

	if key_or_error has not key {
		debug.write_line('System call: futex: Failed to get the futex key')
		return key_or_error.error
	}

	operation = operation_and_flags & 0x7f

	return when (operation) {
		FUTEX_OPERATION_WAIT => Futexes.wait(key, operation, value_1, value_2, value_3),
		FUTEX_OPERATION_WAIT_BITSET => Futexes.wait(key, operation, value_1, value_2, value_3),
		FUTEX_OPERATION_WAKE => Futexes.wake(key, operation, value_1, value_3),
		FUTEX_OPERATION_WAKE_BITSET => Futexes.wake(key, operation, value_1, value_3),
		else => {
			debug.write_line('System call: Futex: Unsupported operation')
			EINVAL
		}
	}
}