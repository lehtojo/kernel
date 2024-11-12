namespace kernel.system_calls

plain SystemStatistics {
   uptime: u64
   loads: u64[3]
   total_ram: u64
   free_ram: u64
   shared_ram: u64
   buffer_ram: u64
   total_swap: u64
   free_swap: u64
   process_count: u64
   padding: u8[22]
}

# System call: sysinfo
export system_sysinfo(statistics: SystemStatistics): u64 {
   debug.write('System call: sysinfo: statistics=')
   debug.write_address(statistics)
   debug.write_line()

   # Todo: Remove hard-coded values
   statistics.uptime = 60
   statistics.loads[0] = 42
   statistics.loads[1] = 7
   statistics.loads[2] = 3
   statistics.total_ram = 2 * GiB
   statistics.free_ram = statistics.total_ram / 2
   statistics.shared_ram = 0
   statistics.buffer_ram = 0
   statistics.total_swap = 0
   statistics.free_swap = 0
   statistics.process_count = interrupts.scheduler.processes.size

   return 0
}
