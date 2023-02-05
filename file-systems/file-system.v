namespace kernel.file_systems

FileSystem {
	shared root: FileSystem

	open mount_root()
	open mount()

	open open_file(base: Custody, path: String, flags: i32, mode: u32): Result<OpenFileDescription, u32>
	open create_file(base: Custody, path: String, flags: i32, mode: u32): Result<OpenFileDescription, u32>
	open make_directory(base: Custody, path: String, flags: i32, mode: u32): Result<OpenFileDescription, u32>
	open link()
	open unlink()
	open symbolic_link()
	open remove_directory()
	open change_mode()
	open change_owner()
	open access()
	open lookup_metadata()
	open time()
	open rename()
	open open_directory()
}