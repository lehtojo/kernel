namespace kernel.file_systems

constant O_CREAT = 0x40
constant O_RDONLY = 0
constant O_WRONLY = 1

constant CREATE_OPTION_NONE = 0
constant CREATE_OPTION_FILE = 1
constant CREATE_OPTION_DIRECTORY = 2

PathParts {
	private path: String
	private position: u64

	part: String
	ended => position == path.length

	init(path: String) {
		this.path = path
		this.position = 0
		this.part = String.empty()

		# Skip the root separator automatically
		if path.starts_with(`/`) { position++ }
	}

	next(): bool {
		# If we have reached the end, there are no parts left
		if position == path.length return false

		separator = path.index_of(`/`, position)

		# If there is no next separator, return the remaining path 
		if separator < 0 {
			part = path.slice(position)
			position = path.length # Go to the end of the path
			return true
		}

		# Store the part before the found separator
		part = path.slice(position, separator)

		# Find the next part after the separator
		position = separator + 1
		return true
	}
}

plain DirectoryEntry {
	name: String
	inode: u64
	type: u8
}

DirectoryIterator {
	open next(): bool
	open value(): DirectoryEntry

	iterator(): DirectoryIterator { return this }
}

FileSystem {
	id: u32

	open get_block_size(): u32

	open mount_root()
	open mount()

	open open_file(base: Custody, path: String, flags: i32, mode: u32): Result<OpenFileDescription, u32>
	open create_file(base: Custody, path: String, flags: i32, mode: u32): Result<OpenFileDescription, u32>
	open make_directory(base: Custody, path: String, flags: i32, mode: u32): Result<OpenFileDescription, u32>
	open access(base: Custody, path: String, mode: u32): u64
	open lookup_status(base: Custody, path: String, metadata: FileMetadata): u64
	open lookup_extended_status(base: Custody, path: String, metadata: FileMetadataExtended): u64
	open link()
	open unlink()
	open symbolic_link()
	open remove_directory()
	open change_mode()
	open change_owner()
	open time()
	open rename()
	open open_directory()

	open iterate_directory(allocator: Allocator, inode: Inode): Result<DirectoryIterator, u32>
	open allocate_inode_index(): u64
	open open_path(allocator: Allocator, container: Custody, path: String, create_options: u8): Result<Custody, u32>
}