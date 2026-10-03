extends Node3D

func select():
	var positions = %MonitorPositions.get_children(true)
	for child in positions:
		if child.get_child_count() > 0:
			var monitor = child.get_children()[0]
			monitor.generate_useable_monitor()

func interact():
	# emit a signal that you're hiding.
	# if hiding is true, player collision is turned off and cannot be spotted.
	# A check -> while visible, cannot hide, can only hide if manager cannot see you?
	print("Started hiding in desk!")
	SignalBus.is_hiding.emit(true)
