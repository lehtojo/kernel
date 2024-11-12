namespace kernel.system_calls

import kernel.time

# System call: time
export system_time(): u64 {
   debug.write_line('System call: time')

   # Attempt to fetch the current time
   now = DateTime()
   result = Time.instance.get_time(now)
   if result != 0 return result

   return now.unix_seconds()
}
