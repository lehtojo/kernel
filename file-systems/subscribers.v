namespace kernel.file_systems

pack Subscribers {
	subscribers: List<Blocker>

	shared new(allocator: Allocator): Subscribers {
		return pack { subscribers: List<Blocker>(allocator) using allocator } as Subscribers
	}

	subscribe(subscriber: Blocker): _ {
		debug.write_line('Subscribers: Subscribing...')
		subscribers.add(subscriber)
	}

	unsubscribe(subscriber: Blocker): _ {
		debug.write_line('Subscribers: Unsubscribing...')
		subscribers.remove(subscriber)
	}

	update(): _ {
		#debug.write_line('Subscribers: Updating subscribers')
		if subscribers.size == 0 return

		loop (i = 0, i < subscribers.size, i++) {
			subscriber = subscribers[i]

			# Switch the paging table to the process of the subscriber, because it may need to access the process memory
			subscriber.process.memory.paging_table.use()

			# Update the subscriber
			subscriber.update()
		}

		# Switch back to the current process paging table
		interrupts.scheduler.current.memory.paging_table.use()
	}

	destruct(): _ {
		subscribers.destruct()
	}
}