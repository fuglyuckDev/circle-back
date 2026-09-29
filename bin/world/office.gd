extends Node3D

@onready var player := $Player
var desk_groups : Array

func _ready() -> void:
	desk_groups = %Desks.get_children(false)
	for deskGroup in desk_groups:
		var desks = deskGroup.get_children(false)
		var selected_desk_for_group = _get_random_desk(desks)
		selected_desk_for_group.select()
	SignalBus.ui_popup.emit("Press 'E' to push code.")

func _get_random_desk(array: Array) -> Node3D:
	var array_size = array.size()
	var random_number = randi() % array_size
	return array[random_number]

func _exit_tree() -> void:
	GameState.useable_monitors = 0
	GameState.completed_tasks = 0
