namespace kernel.elf32

plain SectionHeader {
	name: u32
	type: u32
	flags: u32
	virtual_address: u32
	offset: u32
	section_file_size: u32
	link: u32
	info: u32
	alignment: u32
	entry_size: u32
}