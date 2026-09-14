extends Node

var useable_monitors : int = 8
var completed_tasks : int = 0
var total_tasks : int = 8

func _ready() -> void:
	SignalBus.task_complete.connect(_on_task_complete)

func _on_task_complete():
	completed_tasks + 1
	if completed_tasks == 8:
		end_game()

func end_game():
	get_tree().change_scene_to_file("res://bin/ui/start_menu/start_menu.tscn")
