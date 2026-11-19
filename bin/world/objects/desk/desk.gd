extends Node3D

var is_targeted : bool = false

func select():
	var positions = %MonitorPositions.get_children(true)
	for child in positions:
		if child.get_child_count() > 0:
			var monitor = child.get_children()[0]
			monitor.generate_useable_monitor()

func interact():
	SignalBus.is_hiding.emit(true)

func targeted():
	is_targeted = true

func untarget():
	is_targeted = false
