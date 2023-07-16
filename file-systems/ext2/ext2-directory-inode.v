namespace kernel.file_systems.ext2

import kernel.system_calls
import kernel.devices

Ext2Inode Ext2DirectoryInode {
	inodes: List<Inode>

	init(allocator: Allocator, file_system: FileSystem, index: u64, name: String) {
		Ext2Inode.init(allocator, file_system, index, name)
		this.inodes = List<Inode>(allocator) using allocator
	}

	override is_directory() { return true }

	override create_child(name: String, mode: u16, device: u64) {
		# Output debug information
		is_device = has_flag(mode, S_IFCHR) or has_flag(mode, S_IFBLK)

		if is_device {
			debug.write('Ext2 directory inode: Creating a device ')
			debug.write(device)
			debug.write(' with name ')
			debug.write_line(name)
		} else {
			debug.write('Ext2 directory inode: Creating a child with name ') debug.write_line(name)
		}

		# Allocate an inode index for the child
		child_index = file_system.allocate_inode_index()
		if child_index == -1 return none as Inode

		panic('Todo: Write the inode information')

		inode = none as Inode
		is_directory = (mode & S_IFMT) == S_IFDIR

		# Create a directory or a normal inode based on the arguments
		if is_directory { inode = Ext2DirectoryInode(allocator, file_system, child_index, name.copy(allocator)) using allocator }
		else { inode = Ext2Inode(allocator, file_system, child_index, name.copy(allocator)) using allocator }

		# Save metadata
		inode.metadata.mode = mode

		# If we are creating a device, write the device major and minor numbers
		if is_device { inode.metadata.device = device }

		inodes.add(inode)

		return inode
	}

	# Summary: Iterates all directory entries (unloaded as well) and loads an inode if it has the specified name
	private lookup_unloaded(name: String): Inode {
		local_allocator = LocalHeapAllocator()

		iterator_or_error = file_system.iterate_directory(local_allocator, this)

		if iterator_or_error.has_error {
			debug.write_line('Ext2 directory inode: Failed to iterate directory for inode lookup')
			local_allocator.deallocate()
			return none as Inode
		}

		iterator = iterator_or_error.value
		inode = none as Inode

		loop entry in iterator {
			if not (entry.name == name) continue

			inode_allocator = LocalHeapAllocator(allocator)

			if entry.type == DT_DIR {
				debug.write_line('Ext2 directory inode: Creating a directory inode...')
				inode = Ext2DirectoryInode(allocator, file_system, entry.inode, entry.name.copy(inode_allocator)) using inode_allocator
			} else {
				debug.write_line('Ext2 directory inode: Creating an inode...')
				inode = Ext2Inode(allocator, file_system, entry.inode, entry.name.copy(inode_allocator)) using inode_allocator
			}

			# Load information about the inode
			information: InodeInformation = inode.(Ext2Inode).information
			result = file_system.(Ext2).load_inode_information(inode.index, information)

			# If loading the information failed, deallocate the inode
			if result != 0 {
				inode_allocator.deallocate()
				inode = none as Inode
			} else {
				# Store the inode for later use
				inodes.add(inode)
			}

			# Stop the loop as we have found the inode
			stop
		}

		local_allocator.deallocate()
		return inode
	}

	override lookup(name: String) {
		debug.write('Ext2 directory inode: Looking for ') debug.write_line(name)

		# If the name is ".", return this directory
		if name == '.' return this

		# Look for an inode with the specified name
		loop (i = 0, i < inodes.size, i++) {
			inode = inodes[i]
			# Todo: That cast is dirty trick, remove it :D 
			if inode.is_directory() and inode.(Ext2DirectoryInode).name == name return inode
			if not inode.is_directory() and inode.(Ext2Inode).name == name return inode
		}

		return lookup_unloaded(name)
	}
}