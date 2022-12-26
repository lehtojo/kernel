pack Optional<T> {
	value: T
	empty: bool

	has_value(): bool {
		return not empty
	}

	get_value(): T {
		return value
	}
}

namespace Optionals {
	new<T>(value: T): Optional<T> {
		return pack { value: value, empty: false } as Optional<T>
	}

	empty<T>(): Optional<T> {
		return pack { value: 0 as T, empty: true } as Optional<T>
	}
}