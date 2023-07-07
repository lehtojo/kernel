namespace kernel.file_systems.ext2

import kernel.devices.storage
import kernel.system_calls

IndirectBlockOperator {
	readable allocator: Allocator
	# Summary: Stores the parent indirect block (optional)
	readable parent: IndirectBlockOperator
	# Summary: Stores the pointers in this indirect block 
	pointers: u32* = 0 as u32*
	# Summary: Stores the number of pointer in this indirect block
	pointer_count: u32 = 0
	# Summary: Stores the current pointer index
	pointer_index: u32 = 0
	# Summary: Stores the number of bytes commited (read/write)
	readable commited: u64*
	# Summary: Stores the number of bytes progressed (read/write)
	readable progress: u64*
	# Summary: Stores the completion progress
	readable end: u64*
	# Summary: Stores the block size of the filesystem
	readable block_size: u32
	# Summary: Stores the number of bytes to read/write
	readable size: u64
	# Summary: Stores the layer of this indirect block
	layer: u8

	init(parent: IndirectBlockOperator) {
		this.allocator = parent.allocator
		this.parent = parent
		this.commited = parent.commited
		this.progress = parent.progress
		this.end = parent.end
		this.block_size = parent.block_size
		this.size = parent.size
		this.layer = parent.layer - 1
	}

	init(allocator: Allocator, commited: u64*, progress: u64*, end: u64*, block_size: u32, size: u64, layer: u8) {
		require(memory.is_aligned(size, block_size), 'Size was not multiple of block sizes')
		this.allocator = allocator
		this.commited = commited
		this.progress = progress
		this.end = end
		this.block_size = block_size
		this.size = size
		this.layer = layer
	}

	open complete(status: u16): _ {
		# Tell the most upper operator we have completed the objective
		if parent !== none parent.complete(status)
	}

	open operate(block: u32): u64 {}

	# Summary: Starts operating by choosing the next block to operate on
	start(): _ {
		require(size > 0, 'Ext2: Can not read nothing')
		commit(0)
	}

	private end_commit(): _ {
		# Advance the parent if such exists
		if parent !== none {
			parent.next()
			return
		}

		# We have reached the end of commits, the number of commited bytes determines the end progress
		end[] = commited[]
	}

	# Summary: Chooses the next block to operate on
	open next(): bool {
		loop (pointer_index < pointer_count, pointer_index++) {
			# Find the next non-zero pointer
			pointer = pointers[pointer_index]
			if pointer != 0 return true
		}

		return false
	}

	# Summary: Commits the specified number of bytes
	commit(commit: u64): _ {
		loop {
			commited[] += commit

			# Stop advancing once we have commited the specified number of bytes
			if commited[] >= size {
				# We have reached the end of commits, the number of commited bytes determines the end progress
				end[] = commited[]
				return
			}

			# If we have reached the end of this layer, set the commited number of bytes as the end progress
			if pointer_index >= pointer_count {
				end_commit()
				return
			}

			# Choose the next block to operate on
			if not next() {
				end_commit()
				return
			}

			# Load the block and go over it so it will not reoperated
			pointer = pointers[pointer_index]
			pointer_index++

			# Operate the block and store the number of commited bytes
			commit = operate(pointer)
			if commit == 0 return
		}
	}

	# Summary: Progresses forward the specified number of bytes
	progress(bytes: u64): _ {
		progress[] += bytes

		debug.write('Ext2: Progress: ') debug.write(progress[]) debug.put(`/`) debug.write_line(end[])

		# Complete once the progress has been completed
		if progress[] >= end[] complete(0)
	}

	# Summary: Completes the specified error status
	fail(error: u16): _ {
		complete(error)
	}
}