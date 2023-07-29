# HPET = High Precision Event Timer
namespace kernel.hpet

import kernel.interrupts

constant HEADER_COMPARATOR_COUNT_MASK = 0b11111

constant CAPABILITIES_REGISTER_OFFSET = 0x0
constant CONFIGURATION_REGISTER_OFFSET = 0x10
constant MAIN_COUNTER_REGISTER_OFFSET = 0xF0

constant CONFIGURATION_ENABLED = 1
constant CONFIGURATION_LEGACY_MAPPING_ENABLED = 1 <| 1

constant CAPABILITIES_LEGACY_MAPPING_SUPPORTED = 1 <| 15
constant CAPABILITIES_64_BIT = 1 <| 13
constant CAPABILITIES_TIMER_COUNT_OFFSET = 8
constant CAPABILITIES_TIMER_COUNT_MASK = 0b1111
constant CAPABILITIES_TICK_PERIOD_OFFSET = 32

constant TIMER_FLAG_FSB_SUPPORT = 1 <| 15
constant TIMER_FLAG_FSB_ENABLED = 1 <| 14
constant TIMER_INTERRUPT_OFFSET = 9
constant TIMER_INTERRUPT_MASK = 0b11111
constant TIMER_FLAG_ALLOW_SETTING_ACCUMULATOR = 1 <| 6
constant TIMER_FLAG_PERIODIC_MODE_SUPPORT = 1 <| 4
constant TIMER_FLAG_PERIODIC_MODE_ENABLED = 1 <| 3
constant TIMER_FLAG_INTERRUPTS_ENABLED = 1 <| 2
constant TIMER_INTERRUPT_ROUTINGS_OFFSET = 32

timer_configuration(i: i32): i32 { return 0x100 + 0x20 * i }
timer_comparator(i: i32): i32 { return 0x108 + 0x20 * i }
timer_fsb_interrupt_route(i: i32): i32 { return 0x110 + 0x20 * i }

read_u32(registers: link, offset: u32): u32 {
	return (registers + offset).(u32*)[]
}

read_u64(registers: link, offset: u32): u64 {
	lower = (registers + offset).(u32*)[0] as u64
	upper = (registers + offset).(u32*)[1] as u64
	return (upper <| 32) | lower
}

write_u32(registers: link, offset: u32, value: u32): _ {
	(registers + offset).(u32*)[] = value
}

write_u64(registers: link, offset: u32, value: u64): _ {
	(registers + offset).(u32*)[0] = value
	(registers + offset).(u32*)[1] = (value |> 32)
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
	manager: TimerManager
	periodic: bool
	fsb: bool

	is_64_bit => manager.is_64_bit
	registers => manager.registers

	shared new(id: u32, manager: TimerManager, periodic: bool, fsb: bool): Timer {
		return pack { id: id, manager: manager, periodic: periodic, fsb: fsb } as Timer
	}

	is_ioapic_line_supported(line: u8): bool {
		configuration = read_u64(registers, timer_configuration(id))
		supported_lines = configuration |> TIMER_INTERRUPT_ROUTINGS_OFFSET
		return has_flag(supported_lines, 1 <| line)
	}

	enable_periodic_mode_with_ioapic_interrupt(interrupt: u8, period: u64): _ {
		debug.write('HPET: Configuring timer ') debug.write(id) debug.write_line(' to periodic mode using IOAPIC interrupt routing: ')
		debug.write('HPET: Interrupt = ') debug.write_line(interrupt)
		debug.write('HPET: Period = ') debug.write(period) debug.write_line(' tick(s)')

		require(periodic, 'HPET: Can not enable periodic mode on a non-periodic timer')
		require(interrupt <= TIMER_INTERRUPT_MASK, 'HPET: Invalid interrupt for a timer')

		configuration = read_u64(registers, timer_configuration(id))
		configuration |= TIMER_FLAG_INTERRUPTS_ENABLED
		configuration |= TIMER_FLAG_PERIODIC_MODE_ENABLED
		configuration |= TIMER_FLAG_ALLOW_SETTING_ACCUMULATOR
		configuration &= !TIMER_FLAG_FSB_ENABLED
		configuration |= (interrupt <| TIMER_INTERRUPT_OFFSET)

		now = read_u64(registers, MAIN_COUNTER_REGISTER_OFFSET) # Note: 64-bit read will work with 32-bit timers

		# Write back the modified configuration
		write_u64(registers, timer_configuration(id), configuration)

		if is_64_bit {
			write_u64(registers, timer_comparator(id), now + period)
			write_u64(registers, timer_comparator(id), period)
		} else {
			write_u32(registers, timer_comparator(id), now + period)
			write_u32(registers, timer_comparator(id), period)
		}
	}

	enable_periodic_mode_with_fsb_interrupt(interrupt: u8, period: u64): _ {
		debug.write('HPET: Configuring timer ') debug.write(id) debug.write_line(' to periodic mode using FSB interrupt routing: ')
		debug.write('HPET: Interrupt = ') debug.write_line(interrupt)
		debug.write('HPET: Period = ') debug.write(period) debug.write_line(' tick(s)')

		require(periodic, 'HPET: Can not enable periodic mode on a non-periodic timer')
		require(fsb, 'HPET: Timer does not support FSB interrupt routing')

		configuration = read_u64(registers, timer_configuration(id)) # Read the configuration without the interrupt routing
		configuration |= TIMER_FLAG_INTERRUPTS_ENABLED
		configuration |= TIMER_FLAG_PERIODIC_MODE_ENABLED
		configuration |= TIMER_FLAG_ALLOW_SETTING_ACCUMULATOR
		configuration |= TIMER_FLAG_FSB_ENABLED

		now = read_u64(registers, MAIN_COUNTER_REGISTER_OFFSET) # Note: 64-bit read will work with 32-bit timers

		# Write back the modified configuration
		write_u64(registers, timer_configuration(id), configuration)

		if is_64_bit {
			write_u64(registers, timer_comparator(id), now + period)
			write_u64(registers, timer_comparator(id), period)
		} else {
			write_u32(registers, timer_comparator(id), now + period)
			write_u32(registers, timer_comparator(id), period)
		}

		# Use FSB interrupt routing:
		# Compute the address where the timer will write the data below upon interrupt.
		# Basically writing to the address will cause the wanted interrupt.
		address = (apic.local_apic_registers_physical_address + apic.LOCAL_APIC_REGISTERS_INTERRUPT_COMMAND_REGISTER) as u64
		data = interrupt # | EDGETRIGGER_FLAG | DEASSERT_FLAG
		write_u64(registers, timer_fsb_interrupt_route(id), (address <| 32) | data)
	}

	reset(): _ {
		if is_64_bit {
			write_u64(registers, timer_comparator(id), 0)
		} else {
			write_u32(registers, timer_comparator(id), 0)
		}
	}
}

plain TimerManager {
	timers: List<Timer>
	registers: link
	is_64_bit: bool
	tick_period: u32

	init(allocator: Allocator) {
		timers = List<Timer>(allocator) using allocator
	}

	attach(registers: link) {
		debug.write('HPET: Registers = ') debug.write_address(registers) debug.write_line()
		this.registers = registers

		capabilities = read_u64(registers, CAPABILITIES_REGISTER_OFFSET)
		is_64_bit = has_flag(capabilities, CAPABILITIES_64_BIT)

		tick_period = (capabilities |> CAPABILITIES_TICK_PERIOD_OFFSET) / 1000000
		timer_count = ((capabilities |> CAPABILITIES_TIMER_COUNT_OFFSET) & CAPABILITIES_TIMER_COUNT_MASK) + 1
		is_legacy_mapping_supportd = has_flag(capabilities, CAPABILITIES_LEGACY_MAPPING_SUPPORTED)

		debug.write('HPET: Tick period = ') debug.write(tick_period) debug.write_line('ns')
		debug.write('HPET: Timer count = ') debug.write_line(timer_count)
		debug.write('HPET: 64-bit timers = ') debug.write_line(is_64_bit)
		debug.write('HPET: Legacy mapping supported = ') debug.write_line(is_legacy_mapping_supportd)

		# Track whether we find a timer with periodic mode
		found_periodic_timer = false

		loop (i = 0, i < timer_count, i++) {
			configuration = read_u64(registers, timer_configuration(i))
			debug.write('HPET: Timer ') debug.write(i) debug.write(' configuration = ') debug.write_address(configuration) debug.write_line()

			fsb = has_flag(configuration, TIMER_FLAG_FSB_SUPPORT)
			debug.write('HPET: Timer ') debug.write(i) debug.write(' has FSB support = ') debug.write_line(fsb)

			# Determine whether this timer has support for periodic mode
			periodic = has_flag(configuration, TIMER_FLAG_PERIODIC_MODE_SUPPORT)
			found_periodic_timer |= periodic

			timer = Timer.new(i, this, periodic, fsb)
			timer.reset()

			timers.add(timer)
		}

		# Verify we have at least one timer and one with periodic mode
		require(timers.size > 0 and found_periodic_timer, 'HPET: Can not operate with the current timers')
	}

	find_timer(periodic: bool, fsb: bool): Optional<Timer> {
		loop (i = 0, i < timers.size, i++) {
			timer = timers[i]
			if timer.periodic != periodic or timer.fsb != fsb continue

			return Optionals.new<Timer>(timer)
		}

		return Optionals.empty<Timer>()
	}

	enable_all() {
		debug.write_line('HPET: Enabling all timers...')
		value = read_u32(registers, CONFIGURATION_REGISTER_OFFSET)
		value |= CONFIGURATION_ENABLED
		value &= !CONFIGURATION_LEGACY_MAPPING_ENABLED
		write_u32(registers, CONFIGURATION_REGISTER_OFFSET, value)
	}

	reset() {
		debug.write_line('HPET: Resetting all timers...')
		write_u64(registers, MAIN_COUNTER_REGISTER_OFFSET, 0)
	}

	print() {
		debug.write_line('HPET: Timers: ')

		loop (i = 0, i < timers.size, i++) {
			timer = timers[i]

			debug.write('HPET: Timer ') debug.write(timer.id)

			if timer.periodic {
				debug.write_line(' (periodic)')
			} else {
				debug.write_line()
			}
		}
	}
}

create_scheduler_timer(manager: TimerManager): _ {
	debug.write_line('HPET: Creating scheduler timer...')

	# Compute the number of ticks needed for the wanted period
	period_in_milliseconds = 10
	period_in_nanoseconds = period_in_milliseconds * 1000000
	period_in_ticks = period_in_nanoseconds / manager.tick_period

	# Attempt to find a timer with periodic mode and FSB support
	if manager.find_timer(true, true) has timer {
		debug.write_line('HPET: Using FSB timer for scheduler')
		timer.enable_periodic_mode_with_fsb_interrupt(HPET_INTERRUPT, period_in_ticks)
		return
	}

	debug.write_line('HPET: Found no timer with periodic mode and FSB support, attempting IOAPIC...')

	# Attempt to find a timer with periodic mode
	require(manager.find_timer(true, false) has legacy_timer, 'HPET: Failed to find a timer with periodic mode')

	# We do not like IOAPIC interrupt routing, so the timer better support the IOAPIC line we want :^D
	ioapic_line = HPET_INTERRUPT - INTERRUPT_BASE
	require(legacy_timer.is_ioapic_line_supported(ioapic_line), 'HPET: Legacy timer does not support the wanted IOAPIC line')

	legacy_timer.enable_periodic_mode_with_ioapic_interrupt(ioapic_line, period_in_ticks)
	ioapic.redirect(ioapic_line, 0) # Todo: CPU id?
}

export initialize(allocator: Allocator, header: HPETHeader*) {
	registers = mapper.map_kernel_page(header[].address.address as link, MAP_NO_CACHE)
	require(registers !== none, 'HPET: Missing registers')

	debug.write('HPET: Registers = ')
	debug.write_address(registers)
	debug.write_line()

	debug.write('HPET: Comparator count = ')
	comparator_count = (header[].information & HEADER_COMPARATOR_COUNT_MASK) as i64 
	debug.write_line(comparator_count)

	manager = TimerManager(allocator) using allocator
	manager.attach(registers)
	manager.reset()
	manager.enable_all()

	create_scheduler_timer(manager)

	manager.print()
}