namespace kernel.low

import 'C' uefi_call_wrapper(function: link, argument_0: u64, argument_1: u64): u64

call_uefi(function: link, argument_0, argument_1) {
	debug.write('UEFI: Calling ') debug.write_address(function) debug.write(' with arguments ')
	debug.write_address(argument_0 as u64) debug.write(', ') debug.write_address(argument_1 as u64) debug.write_line()
	return uefi_call_wrapper(function, argument_0 as u64, argument_1 as u64)
}

$uefi_scope!(uefi, body) {
	$previous_paging_table = read_cr3()
	write_cr3($uefi.paging_table)
	$body
	write_cr3($previous_paging_table)
}

plain UefiTableHeader {
	signature: u64
	revision: u32
	header_size: u32
	crc32: u32
	reserved: u32
}

pack UefiGuid {
	data1: u32
	data2: u16
	data3: u16
	data4: u64

	shared new(data1: u32, data2: u16, data3: u16, data4_1: u8, data4_2: u8, data4_3: u8, data4_4: u8, data4_5: u8, data4_6: u8, data4_7: u8, data4_8: u8): UefiGuid {
		data4: u64 = data4_1 | (data4_2 <| 8) | (data4_3 <| 16) | (data4_4 <| 24) | (data4_5 <| 32) | (data4_6 <| 40) | (data4_7 <| 48) | (data4_8 <| 56)
		return pack { data1: data1, data2: data2, data3: data3, data4: data4 } as UefiGuid
	}
}

pack UefiConfigurationTable {
	vendor_guid: UefiGuid
	vendor_table: link
}

plain UefiSystemTable {
	inline header: UefiTableHeader
	firmware_vendor: link
	firmware_revision: u32
	padding: u32
	console_in_handle: link
	console_in: link
	console_out_handle: link
	console_out: link
	console_error_handle: link
	console_error: link
	runtime_services: UefiRuntimeServices
	boot_services: link
	number_of_table_entries: u64
	configuration_table: UefiConfigurationTable*
}

plain UefiRuntimeServices {
	inline header: UefiTableHeader
	get_time: link
	set_time: link
	get_wakeup_time: link
	set_wakeup_time: link
	set_virtual_adress_map: link
	convert_pointer: link
	get_variable: link
	get_next_variable_name: link
	set_variable: link
	get_next_high_monotonic_count: link
	reset_system: link
	update_capsule: link
	query_capsule_capabilities: link
	query_variable_info: link
}

pack UefiGraphicsInformation {
	framebuffer_physical_address: u64
	horizontal_stride: u64
	width: u64
	height: u64

	framebuffer_space_size => width * height * sizeof(u32)
}

plain UefiInformation {
	system_table: UefiSystemTable
	regions: Segment*
	region_count: u64
	physical_memory_size: u64
	memory_map_end: u64
	bitmap_font_file: link
	bitmap_font_file_size: u64
	bitmap_font_descriptor_file: link
	bitmap_font_descriptor_file_size: u64
	graphics_information: UefiGraphicsInformation
	paging_table: u64
}