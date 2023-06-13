namespace kernel.file_systems

constant S_IFMT = 0xf000
constant S_IFDIR = 0x4000
constant S_IFCHR = 0x2000
constant S_IFBLK = 0x6000
constant S_IFREG = 0x8000
constant S_IFIFO = 0x1000
constant S_IFLNK = 0xa000
constant S_IFSOCK = 0xc000

constant S_ISUID = 0x800
constant S_ISGID = 0x400
constant S_ISVTX = 0x200
constant S_IRUSR = 0x100     # User (owner) read
constant S_IWUSR = 0x80      # User (owner) write
constant S_IXUSR = 0x40      # User (owner) execute 
constant S_IREAD = S_IRUSR
constant S_IWRITE = S_IWUSR
constant S_IEXEC = S_IXUSR
constant S_IRGRP = 0x20      # Group read
constant S_IWGRP = 0x10      # Group write
constant S_IXGRP = 0x8       # Group execute
constant S_IROTH = 0x4       # Others read
constant S_IWOTH = 0x2       # Others write
constant S_IXOTH = 0x1       # Others execute

constant S_IRWXU = S_IRUSR | S_IWUSR | S_IXUSR # User (owner) read, write, execute

constant S_IRWXG = S_IRWXU |> 3  # Group read, write, execute
constant S_IRWXO = S_IRWXG |> 3  # Others read, write, execute

plain FileMetadata {
	device_id: u64
	inode: u64
	hard_link_count: u64
	mode: u32
	uid: u32
	gid: u32
	padding_1: u32
	rdev: u64
	size: u64
	block_size: u64
	blocks: u64
	last_access_time: u64
	padding_2: u64
	last_modification_time: u64
	padding_3: u64
	last_change_time: u64
}

pack Timestamp {
	seconds: u64
	nanoseconds: u64
}

plain FileMetadataExtended {
	mask: u32
	block_size: u32
	attributes: u64
	hard_link_count: u32
	uid: u32
	gid: u32
	mode: u32
	inode: u64
	size: u64
	blocks: u64
	attributes_mask: u64
	last_access_time: Timestamp
	creation_time: Timestamp
	last_change_time: Timestamp
	last_modification_time: Timestamp
	device_major: u32
	device_minor: u32
	file_system_device_major: u32
	file_system_device_minor: u32
	mount_id: u64
}