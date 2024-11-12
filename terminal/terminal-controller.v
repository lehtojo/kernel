namespace kernel.terminal

TerminalController {
	open write_raw(data: Array<u8>, size: u64): _
	open set_background_color(color: u32): _
	open set_foreground_color(color: u32): _
	open reset_attributes(): _
}