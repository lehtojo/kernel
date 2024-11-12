namespace kernel.system_calls

# System call: readlink
export system_readlink(path_argument: link, buffer: link, buffer_size: u64): u64 {
   debug.write('System call: readlink: ')
   debug.write('path=') debug.write_address(path_argument)
   debug.write(', buffer=') debug.write_address(buffer)
   debug.write(', buffer_size=') debug.write(buffer_size)
   debug.write_line()

   process = get_process()

   local_allocator = LocalHeapAllocator()

   # Verify the specified buffer is valid
   if not is_valid_region(process, buffer, buffer_size, true) {
      debug.write_line('System call: readlink: Invalid output buffer')

      local_allocator.deallocate()
      return EINVAL
   }

   # Load the path as a string object
   if load_string(local_allocator, process, path_argument, PATH_MAX) has not path {
      debug.write_line('System call: readlink: Failed to load the path')

      local_allocator.deallocate()
      return EINVAL
   }

   # Load the custody of the container
   container_custody_or_error = load_custody(local_allocator, process, AT_FDCWD, path)

   if container_custody_or_error.has_error {
      debug.write_line('System call: readlink: Failed to load container custody from path')

      local_allocator.deallocate()
      return container_custody_or_error.error
   }

   container_custody = container_custody_or_error.value
   result_path_or_error = FileSystems.root.read_link(local_allocator, container_custody, path)

   if result_path_or_error.has_error {
      debug.write_line('System call: readlink: Failed to resolve symbolic link path')

      local_allocator.deallocate()
      return result_path_or_error.error
   }

   result_path = result_path_or_error.value

   # Verify the provided buffer is large enough
   if result_path.length > buffer_size {
      debug.write_line('System call: readlink: Too small buffer')

      local_allocator.deallocate()
      return ENAMETOOLONG
   }

   # Output the symbolic link path
   memory.copy(buffer, result_path.data, result_path.length)

   local_allocator.deallocate()
   return result_path.length
}
