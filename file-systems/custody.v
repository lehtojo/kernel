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
}