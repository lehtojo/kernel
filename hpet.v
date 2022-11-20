# HPET = High Precision Event Timer
namespace kernel.hpet

constant MAIN_COUNTER_REGISTER = 0xF0

pack AddressStructure {
	address_space_id: u8 # 0: System memory, 1: System I/O
	register_bit_width: u8
	register_bit_offset: u8
	reserved: u8
	address: u64
}

pack HPETHeader {
	header: SDTHeader
	hardware_revision_id: u8
	information: u8
	pci_vendor_id: u16
	address: AddressStructure
	hpet_number: u8
	minimum_tick: u16
	page_protection: u8
}

pack Timer {
	id: u32
	registers: u64*
	periodic: bool

	shared new(id: u32, registers: u64*, periodic: bool): Timer {
		return pack { id: id, registers: registers, periodic: periodic } as Timer
	}

	private shared timer_configuration(i: i32): i32 {
		return 0x100 + 0x20 * i
	}

	private shared timer_comparator(i: i32): i32 {
		return 0x108 + 0x20 * i
	}

	periodic(interrupt: u8, period: u64) {
		require(periodic, 'Can not enable periodic mode on a non-periodic timer')

		configuration = (registers + timer_configuration(id))[]
		configuration |= ((interrupt <| 9) | (1 <| 2) | (1 <| 3) | (1 <| 6))

		now = (registers + MAIN_COUNTER_REGISTER)[]

		(registers + timer_configuration(id))[] = configuration
		(registers + timer_comparator(id))[] = now + period
		(registers + timer_comparator(id))[] = period
	}
}

TimerManager {
	timers: List<Timer>

	shared new(allocator: Allocator): TimerManager {
		manager = allocator.new<TimerManager>()
		manager.timers = Lists.new<Timer>(allocator)
		return manager
	}
}

export print_timer(timer: u64) {
	routes = timer |> 32
	debug.write(timer)
}

export timer_configuration(i: i32): i32 {
	return 0x100 + 0x20 * i
}

export timer_comparator(i: i32): i32 {
	return 0x108 + 0x20 * i
}

export enable_timer(registers: u64*) {
	value = (registers + 0x10)[]
	(registers + 0x10)[] = (value | 1)
}

export initialize(header: HPETHeader*) {
	debug.write('hpet-registers: ')
	registers = header[].address.address as u64*

	debug.write_address(registers)
	debug.write_line()
	require(registers !== none, 'Missing HPET registers')

	debug.write('hpet-register-offset: ')
	offset = header[].address.register_bit_offset
	debug.write_line(offset)

	debug.write('hpet-register-width: ')
	width = header[].address.register_bit_width
	debug.write_line(width)

	debug.write('hpet-comparator-count: ')
	debug.write_line((header[].information & 31) as i64)

	debug.write('hpet-capabilities: ')

	allocator.map_page(registers, registers)
	capabilities = registers[]

	tick_period = (capabilities |> 32) / 1000000
	is_64_bit = (capabilities & 8192) != 0
	timer_count = ((capabilities |> 8) & 15) + 1
	minimum_tick = header[].minimum_tick

	debug.write('tick-period=')
	debug.write(tick_period)
	debug.write('ns, ')
	debug.write('is-64-bit=')
	debug.write(is_64_bit)
	debug.write(', timer-count=')
	debug.write(timer_count)
	debug.write_line()

	debug.write('timers:')
	print_timer((registers + 0x100)[])
	debug.write(', ')
	print_timer((registers + 0x120)[])
	debug.write(', ')
	print_timer((registers + 0x140)[])
	debug.write_line()

	(registers + timer_comparator(0))[] = 0
	(registers + timer_comparator(1))[] = 0
	(registers + timer_comparator(2))[] = 0
	(registers + 0x0F0)[] = 0

	enable_timer(registers)

	timer = Timer.new(0, registers, true)
	timer.periodic(4, 100000000)
}