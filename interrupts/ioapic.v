namespace kernel.interrupts

namespace ioapic {
	constant REDIRECTION_ENTRY_OFFSET = 0x10

	constant DELIVERY_MODE_NORMAL = 0

	registers: u32*

	export initialize(base: u32*) {
		registers = base
	}

	export write_register(index: u8, value: u32) {
		# Select the register by writing it to IOREGSEL
		registers[] = index
		registers[4] = value
	}

	export disable(interrupt: u8) {
		value = 1 <| 16 # Disable the redirection entry
		register = 0x10 + interrupt * 2 # Compute the index of the first register associated with the specified interrupt
		write_register(register, value)
		write_register(register + 1, 0)
	}

	export redirect(index: u64, interrupt_vector: u8, delivery_mode: u8, logical_destination: bool, active_low: bool, trigger_level_mode: bool, masked: bool, destination: u8) {
		redirection_entry1: u32 = interrupt_vector | ((delivery_mode & 0b111) <| 8) | (logical_destination <| 11) | (active_low <| 13) | (trigger_level_mode <| 15) | (masked <| 16)
		redirection_entry2: u32 = destination <| 24

		write_register((index <| 1) + REDIRECTION_ENTRY_OFFSET, redirection_entry1)
		write_register((index <| 1) + REDIRECTION_ENTRY_OFFSET + 1, redirection_entry2)
	}

	export redirect(interrupt: u8, cpu: u8) {
		disable(interrupt) # Disable the redirection entry before changing it

		# 0-7   = Vector															: "It seems to be the interrupt number to be called"
		# 8-10  = Delivery mode													: "It seems to be about priority" 
		# 11    = Destination mode (0: Physical destination, 1: Logical destination)
		# 12    = Status (0: Idle, 1: Processing)							: "Tells whether an interrupt has been redirected and is being processed"
		# 13    = Pin polarity (0: Active high, 1: Active low)		: "Probably has something to do with detecting signals from voltage"
		# 14    = Remote IRR: ?
		# 15    = Trigger mode (0: Edge, 1: Level)						: "Probably has something to do with detecting signals from voltage"
		# 16    = Mask (0: Enabled, 1: Disabled)							: "Tells whether this redirection is enabled"
		# 56-63 = Destination (Physical destination => APIC ID of CPU, Logical destination => ?)
		delivery = 0      # Fixed
		mode = 0          # Physical destination
		status = 0        # Idle
		polarity = 0      # Active high
		trigger = 0       # Edge

		flags = (INTERRUPT_BASE + interrupt) | (delivery <| 8) | (mode <| 11) | (status <| 12) | (polarity <| 13) | (trigger <| 15)
		destination = cpu # APIC ID of CPU

		register = REDIRECTION_ENTRY_OFFSET + interrupt * 2 # Compute the index of the first register associated with the specified interrupt
		write_register(register + 1, destination) # Write the destination before enabling the redirection entry
		write_register(register, flags)
	}
}