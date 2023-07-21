namespace kernel.devices.gpu

namespace DisplayConnectors {
	private _all: List<GenericDisplayConnector>
	readable current: GenericDisplayConnector

	all(): List<GenericDisplayConnector> {
		if _all === none {
			_all = List<GenericDisplayConnector>(HeapAllocator.instance) using KernelHeap
		}

		return _all
	}

	add(connector: GenericDisplayConnector): _ {
		all.add(connector)
	}

	change(connector: GenericDisplayConnector): _ {
		if current !== none {
			current.disable()
		}

		current = connector
		current.enable()
	}
}