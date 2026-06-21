extends Node3D

func _ready() -> void:
	_get_child_positions(%MousePositions, preload("res://bin/world/objects/mouse/mouse.tscn"))
	_get_child_positions(%MonitorPositions, preload("res://bin/world/objects/monitor/monitor.tscn"))
	_get_child_positions(%KeyboardPositions, preload("res://bin/world/objects/keyboard/keyboard.tscn"))
	_check_if_divider(%DividerTopPos, preload("res://bin/world/objects/desk/dividers/divider_top.tscn"))
	_check_if_divider(%DividerTopPos, preload("res://bin/world/objects/desk/dividers/divider_bottom.tscn"))
	_spawn_clutter(%Clutter)

func _get_child_positions(parent:Node3D, object: PackedScene):
	var object_instance = object.instantiate()
	var markers = parent.get_children()
	var random_index = randi_range(0, markers.size() - 1)
	var selected_position = markers[random_index]
	selected_position.add_child(object_instance)

func _coin_flip():
	var random_to_one = randi_range(1, 2)
	if random_to_one % 2 == 0:
		return true
	else:
		return false 

func _check_if_divider(marker:Marker3D, object: PackedScene):
	if _coin_flip():
		var object_instance = object.instantiate()
		marker.add_child(object_instance)

func _spawn_clutter(parent:Node3D):
	var scene_path = "res://bin/world/objects/clutter"
	var clutter_dir = DirAccess.open("res://bin/world/objects/clutter")
	var scenes = clutter_dir.get_files()
	var random_index = randi_range(0, scenes.size() - 1)
	var selected_clutter = scenes[random_index]
	var selected_clutter_path = scene_path + "/" + selected_clutter
	_get_child_positions(parent, load(selected_clutter_path))
