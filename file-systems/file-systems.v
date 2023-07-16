namespace kernel.file_systems

namespace FileSystems {
	private all: List<FileSystem>

	root: FileSystem

	initialize(allocator: Allocator): _ {
		all = List<FileSystem>(allocator) using allocator
	}

	add(file_system: FileSystem): _ {
		file_system.id = all.size + 1
		all.add(file_system)
	}

	get(id: u32): FileSystem {
		require(id > 0 and id <= all.size, 'Invalid file system id')
		return all[id - 1]
	}
}