extends Node3D

func select():
	var positions = %MonitorPositions.get_children(true)
	for child in positions:
		if child.get_child_count() > 0:
			var monitor = child.get_children()[0]
			monitor.generate_useable_monitor()
