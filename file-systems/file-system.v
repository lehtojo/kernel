namespace kernel.file_systems

constant O_CREAT = 0x40
constant O_RDONLY = 0
constant O_WRONLY = 1

plain DirectoryEntry {
	name: String
	inode: Inode
	type: u8
}

DirectoryIterator {
	open next(): bool
	open value(): DirectoryEntry

	iterator(): DirectoryIterator { return this }
}

FileSystem {
	shared root: FileSystem
	readable index: u32

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

	open iterate_directory(allocator: Allocator, inode: Inode): DirectoryIterator
	open allocate_inode_index(): u64
	open open_path(allocator: Allocator, container: Custody, path: String, create_options: u8): Result<Custody, u32>
}