namespace kernel.file_systems

plain InodeMetadata {
	mode: u32
	major_device: u32
	minor_device: u32

	is_directory => (mode & S_IFMT) == S_IFDIR
	is_character_device => (mode & S_IFMT) == S_IFCHR
	is_block_device => (mode & S_IFMT) == S_IFBLK
	is_device => is_character_device or is_block_device
	is_regular_file => (mode & S_IFMT) == S_IFREG 
}