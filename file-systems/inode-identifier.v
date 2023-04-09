namespace kernel.file_systems

pack InodeIdentifier {
	file_system: u32
	inode: u64

	# Summary: Returns a new inode identifier
	shared new(file_system: u32, inode: u64): InodeIdentifier {
		return pack { file_system: file_system, inode: inode } as InodeIdentifier
	}

	# Summary: Prints this inode identifier to the console
	print(): _ {
		debug.put(`[`)
		debug.write(file_system)
		debug.write(', ')
		debug.write(inode)
		debug.put(`]`)
	}
}