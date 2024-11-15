sort<T>(elements: T*, count: large) {
	quicksort.sort<T>(elements, 0, count - 1)
}

sort<T>(list: List<T>) {
	quicksort.sort<T>(list.data, 0, list.size - 1)
}

sort<T>(elements: T*, count: large, comparator: (T, T) -> large) {
	quicksort.sort<T>(elements, 0, count - 1, comparator)
}

sort<T>(list: List<T>, comparator: (T, T) -> large) {
	quicksort.sort<T>(list.data, 0, list.size - 1, comparator)
}

namespace quicksort

# Summary: Swap the positions of the specified elements
swap(a, b) {
	c = a[]
	a[] = b[]
	b[] = c
}

partition<T>(elements, low, high) {
	pivot = elements[high]
	i = low - 1 # Indicates the right position of pivot so far

	loop (j = low, j <= high - 1, j++) {
		# If the current element is smaller than the pivot, then update the pivot
		if elements[j] < pivot {
			i++ # Update the pivot
			swap(elements + i * strideof(T), elements + j * strideof(T))
		}
	}

	swap(elements + (i + 1) * strideof(T), elements + high * strideof(T))
	return i + 1
}

partition<T>(elements, low, high, comparator) {
	pivot = elements[high]
	i = low - 1 # Indicates the right position of pivot so far

	loop (j = low, j <= high - 1, j++) {
		# If the current element is smaller than the pivot, then update the pivot
		if comparator(elements[j], pivot) < 0 {
			i++ # Update the pivot
			swap(elements + i * strideof(T), elements + j * strideof(T))
		}
	}

	swap(elements + (i + 1) * strideof(T), elements + high * strideof(T))
	return i + 1
}

sort<T>(elements, low, high) {
	if low >= high return

	p = partition<T>(elements, low, high)
	sort<T>(elements, low, p - 1)
	sort<T>(elements, p + 1, high)
}

sort<T>(elements, low, high, comparator) {
	if low >= high return

	p = partition<T>(elements, low, high, comparator)
	sort<T>(elements, low, p - 1, comparator)
	sort<T>(elements, p + 1, high, comparator)
}