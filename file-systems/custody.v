namespace kernel.file_systems

plain Custody {
	shared root: Custody

	name: String
	parent: Custody
	inode: Inode

	init(name: String, parent: Custody, inode: Inode) {
		this.name = name
		this.parent = parent
		this.inode = inode
	}

	destruct_until(allocator: Allocator, custody: Custody) {
		if this === custody return
		if parent === none panic('End custody was never reached')

		parent.destruct_until(allocator, custody)
		allocator.deallocate(this as link)
	}

   path(allocator: Allocator): Result<String, u64> {
      # Compute the length of the path
      length = 0

      loop (custody = this, custody !== none, custody = custody.parent) {
         # Note: Include separator
         length += custody.name.length + 1
      }

      # Verify the path is not too long
      if length > system_calls.PATH_MAX return system_calls.ENAMETOOLONG

      # Attempt to allocate memory for the path
      path = allocator.allocate(length)
      if path === none return system_calls.ENOMEM

      # Copy the path components backwards
      position = length
      
      loop (custody = this, custody !== none, custody = custody.parent) {
         # Copy the path component
         position -= custody.name.length
         memory.copy(path + position, custody.name.data, custody.name.length)

         # Add the path separator
         position--
         path[position] = `/`
      }

      return String.new(path, length)
   }
}
