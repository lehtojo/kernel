pack Result<V, E> {
	value: V
	error: E

	shared from(value: V): Result<V, E> {
		return pack { value: value, error: 0 as E } as Result<V, E>
	}

	shared from(error: E): Result<V, E> {
		return pack { value: 0 as V, error: error } as Result<V, E>
	}

	has_value(): bool {
		return error == 0
	}

	has_error(): bool {
		return not (error == 0)
	}

	get_value(): V {
		return value
	}

	value_or(fallback: V): V {
		if error == 0 return value
		return fallback
	}
}

namespace Results {
	new<V, E>(value: V): Result<V, E> {
		return pack { value: value, error: 0 as E } as Result<V, E>
	}

	error<V, E>(error: E): Result<V, E> {
		return pack { value: 0 as V, error: error } as Result<V, E>
	}
}