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

	reset() {
		(registers + timer_comparator(id))[] = 0
	}
}

TimerManager {
	timers: List<Timer>
	registers: u64*

	init(allocator: Allocator) {
		timers = List<Timer>(allocator) using allocator
	}

	timer_configuration(i: i32): i32 {
		return 0x100 + 0x20 * i
	}

	timer_comparator(i: i32): i32 {
		return 0x108 + 0x20 * i
	}

	attach(registers: u64*) {
		this.registers = registers

		debug.write('hpet-registers: ')
		debug.write_address(registers)
		debug.write_line()

		capabilities = registers[]
		require((capabilities & 0x2000) != 0, 'HPET-timers must be 64-bit')

		tick_period = (capabilities |> 32) / 1000000
		timer_count = ((capabilities |> 8) & 15) + 1

		debug.write('hpet-tick-period=')
		debug.write(tick_period)
		debug.write_line('ns')
		debug.write('hpet-timer-count=')
		debug.write(timer_count)
		debug.write_line()

		loop (i = 0, i < timer_count, i++) {
			configuration = (registers + timer_configuration(i))[]
			periodic = (configuration & 16) != 0

			timer = Timer.new(i, registers, periodic)
			timer.reset()

			timers.add(timer)
		}
	}

	enable_all() {
		value = (registers + 0x10)[]
		(registers + 0x10)[] = (value | 1)
	}

	reset() {
		(registers + 0xF0)[] = 0
	}

	print() {
		debug.write('hpet-timers: ')

		loop (i = 0, i < timers.size, i++) {
			timer = timers[i]

			debug.write('timer ')
			debug.write(timer.id)

			if timer.periodic { debug.write(' (periodic) ') }
			else { debug.put(` `) }
		}

		debug.write_line()
	}
}

export initialize(allocator: Allocator, header: HPETHeader*) {
	registers = header[].address.address as u64*
	require(registers !== none, 'Missing HPET registers')

	debug.write('hpet-registers: ')
	debug.write_address(registers)
	debug.write_line()

	debug.write('hpet-register-offset: ')
	offset = header[].address.register_bit_offset
	debug.write_line(offset)

	debug.write('hpet-register-width: ')
	width = header[].address.register_bit_width
	debug.write_line(width)

	debug.write('hpet-comparator-count: ')
	debug.write_line((header[].information & 31) as i64)

	debug.write('hpet-capabilities: ')

	mapper.map_page(registers, registers)

	manager = TimerManager(allocator) using allocator
	manager.attach(registers)
	manager.reset()
	manager.enable_all()

	manager.timers[0].periodic(4, 100000000)

	manager.print()
}