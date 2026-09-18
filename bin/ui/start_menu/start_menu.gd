extends Node3D

var desk_groups : Array

func _exit_tree() -> void:
	GameState.useable_monitors = 0
	GameState.completed_tasks = 0

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	desk_groups = %Desks.get_children(false)
	for deskGroup in desk_groups:
		var desks = deskGroup.get_children(false)
		var selected_desk_for_group = _get_random_desk(desks)
		selected_desk_for_group.select()

func _get_random_desk(array: Array) -> Node3D:
	var array_size = array.size()
	var random_number = randi() % array_size
	return array[random_number]
	
