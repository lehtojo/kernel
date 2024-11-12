namespace kernel.system_calls

plain StackInformation {
   address: u64
   flags: i32
   size: u64
}

# System call: sigaltstack
export system_sigaltstack(stack: StackInformation, old_stack: StackInformation): u64 {
   debug.write('System call: sigaltstack: ')
   debug.write('stack=') debug.write_address(stack)
   debug.write(', old_stack=') debug.write_address(old_stack)
   debug.write_line()

   return 0
}
