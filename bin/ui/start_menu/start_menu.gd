extends Node3D

func _exit_tree() -> void:
	GameState.completed_tasks = 0
	GameState.total_tasks = 8
	GameState.useable_monitors = 8

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
