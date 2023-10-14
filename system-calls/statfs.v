namespace kernel.system_calls

# System call: statfs
export system_statfs(path_argument: link, information: FileSystemInformation): u64 {
	debug.write('System call: statfs: ')
	debug.write('path=') debug.write_address(path_argument)
	debug.write(', information=') debug.write_address(information)
	debug.write_line()

   process = get_process()

   local_allocator = LocalHeapAllocator()

   # Verify the specified file system information structure is valid
   if not is_valid_region(process, information as link, sizeof(FileSystemInformation), true) {
      debug.write_line('System call: statfs: Invalid output buffer')

      local_allocator.deallocate()
      return EINVAL
   }

   # Load the path as a string object
   if load_string(local_allocator, process, path_argument, PATH_MAX) has not path {
      debug.write_line('System call: statfs: Failed to load the path')

      local_allocator.deallocate()
      return EINVAL
   }

   # Load the custody of the container
   container_custody_or_error = load_custody(local_allocator, process, AT_FDCWD, path)

   if container_custody_or_error.has_error {
      debug.write_line('System call: statfs: Failed to load container custody from path')

      local_allocator.deallocate()
      return container_custody_or_error.error
   }

   container_custody = container_custody_or_error.value

   # Load the custody of the path now that we have the container
   custody_or_error = FileSystems.root.open_path(local_allocator, container_custody, path, CREATE_OPTION_NONE)

   if custody_or_error.has_error {
      debug.write_line('System call: statfs: Failed to load custody from path')

      local_allocator.deallocate()
      return container_custody_or_error.error
   }

   custody = custody_or_error.value
   inode = custody.inode

   # Verify we have an inode
   if inode === none {
      debug.write_line('System call: No attached inode')

      local_allocator.deallocate()
      return EINVAL
   }

   # Load information about the filesystem that contains the inode
	return inode.file_system.load_information(information)
}

# System call: fstatfs
export system_fstatfs(file_descriptor: i64, information: FileSystemInformation): u64 {
	debug.write('System call: fstatfs: ')
	debug.write('file_descriptor=') debug.write(file_descriptor)
	debug.write(', information=') debug.write_address(information)
	debug.write_line()

   process = get_process()

   # Verify the specified file system information structure is valid
   if not is_valid_region(process, information as link, sizeof(FileSystemInformation), true) {
      debug.write_line('System call: statfs: Invalid output buffer')
      return EINVAL
   }

   # Load the description associated with the file descriptor
	file_description = process.file_descriptors.try_get_description(file_descriptor)
   if file_description === none return EINVAL

   # Verify we have an inode file
   file = file_description.file
   if not file.is_inode() return EINVAL

   # Load information about the filesystem that contains the inode
   file_system = file.(InodeFile).inode.file_system
	return file_system.load_information(information)
}
