pack Result<V, E> {
	value: V
	error: E

	has_value(): bool {
		return error == 0
	}

	has_error(): bool {
		return not (error == 0)
	}

	get_value(): V {
		return value
	}
}

namespace Results {
	new<V, E>(value: V): Result<V, E> {
		return pack { value: value, error: 0 } as Result<V, E>
	}

	error<V, E>(error: E): Result<V, E> {
		return pack { value: 0, error: error } as Result<V, E>
	}
}