namespace kernel.file_systems

Inode {
	open write_bytes(bytes: Array<u8>): u64
	open read_bytes(destination: link, size: u64): u64
	open lookup(name: String): Inode
}