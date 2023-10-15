namespace kernel.system_calls

# System call: chdir
export system_chdir(path_argument: link): u64 {
   debug.write('System call: chdir: ')
   debug.write('path=') debug.write(path_argument)
   debug.write_line()

   process = get_process()

   local_allocator = LocalHeapAllocator()

   # Todo: Duplicates
   # Load the path as a string object
   if load_string(local_allocator, process, path_argument, PATH_MAX) has not path {
      debug.write_line('System call: chdir: Failed to load the path')

      local_allocator.deallocate()
      return EINVAL
   }

   # Load the custody of the container
   container_custody_or_error = load_custody(local_allocator, process, AT_FDCWD, path)

   if container_custody_or_error.has_error {
      debug.write_line('System call: chdir: Failed to load container custody from path')

      local_allocator.deallocate()
      return container_custody_or_error.error
   }

   container_custody = container_custody_or_error.value

   custody_or_error = FileSystems.root.open_path(local_allocator, container_custody, path, CREATE_OPTION_NONE)

   if custody_or_error.has_error {
      debug.write_line('System call: chdir: Failed to open the path')

      local_allocator.deallocate()
      return custody_or_error.error
   }

   # Update the working folder, since everything is ok
   new_working_directory_or_error = custody_or_error.value.path(HeapAllocator.instance)

   if new_working_directory_or_error.has_error {
      debug.write_line('System call: chdir: Failed to allocate new working directory path')

      local_allocator.deallocate()
      return new_working_directory_or_error.error
   }

   process.working_directory = new_working_directory_or_error.value

   local_allocator.deallocate()
   return 0
}

# System call: fchdir
export system_fchdir(file_descriptor: u64): u64 {
   debug.write('System call: fchdir: ')
   debug.write('file_descriptor=') debug.write(file_descriptor)
   debug.write_line()

   process = get_process()

   # Load the description associated with the file descriptor
	file_description = process.file_descriptors.try_get_description(file_descriptor)
   if file_description === none return EINVAL

   custody = file_description.custody
   require(custody !== none, 'Missing custody')

   # Update the working folder, since everything is ok
   new_working_directory_or_error = custody.path(HeapAllocator.instance)

   if new_working_directory_or_error.has_error {
      debug.write_line('System call: fchdir: Failed to allocate new working directory path')
      return new_working_directory_or_error.error
   }

   process.working_directory = new_working_directory_or_error.value
   return 0
}
