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
constant S_IRUSR = 0x100
constant S_IWUSR = 0x80
constant S_IXUSR = 0x40
constant S_IREAD = S_IRUSR
constant S_IWRITE = S_IWUSR
constant S_IEXEC = S_IXUSR
constant S_IRGRP = 0x20
constant S_IWGRP = 0x10
constant S_IXGRP = 0x8
constant S_IROTH = 0x4
constant S_IWOTH = 0x2
constant S_IXOTH = 0x1

constant S_IRWXU = S_IRUSR | S_IWUSR | S_IXUSR

constant S_IRWXG = S_IRWXU |> 3
constant S_IRWXO = S_IRWXG |> 3

pack TimeSpecification {
	seconds: u64
	nanoseconds: u32
}

plain FileMetadata {
	device_id: u32
	padding_1: u32
	inode: u64
	mode: u16
	padding_2: u16
	hard_link_count: u32
	uid: u32
	gid: u32
	rdev: u32
	padding_3: u32
	size: u64
	block_size: u32
	blocks: u32
	last_access_time: TimeSpecification
	last_modification_time: TimeSpecification
	last_change_time: TimeSpecification
}