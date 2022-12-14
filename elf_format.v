namespace kernel.elf

plain SectionHeader {
	name: u32
	type: u32
	flags: u64
	virtual_address: u64
	offset: u64
	section_file_size: u64
	link: u32
	info: u32
	alignment: u64
	entry_size: u64
}