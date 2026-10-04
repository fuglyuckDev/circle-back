extends Node

var useable_monitors : int = 0
var completed_tasks : int = 0

var manager_stage : float = 0

var manager_stage_1 : int = 0
var manager_stage_2 : int = 0
var manager_stage_3 : int = 0

var calc_done := false

func _ready() -> void:
	SignalBus.task_complete.connect(_on_task_complete)
	SignalBus.game_started.connect(_on_game_start)

func _on_task_complete():
	completed_tasks + 1
	_calc_current_stage(manager_stage)

func _on_game_start() -> void:
	if useable_monitors > 0 and !calc_done:
		var stages_calc = useable_monitors / 3
		manager_stage_1 = 0
		manager_stage_2 = stages_calc
		manager_stage_3 = stages_calc * 2
		calc_done = true

func _calc_current_stage(prev_stage) -> void:
	if completed_tasks == manager_stage_1:
		manager_stage = 0.0
	if completed_tasks == manager_stage_2:
		manager_stage = 1.0
	if completed_tasks == manager_stage_3:
		manager_stage = 2.0
	if completed_tasks == useable_monitors:
		manager_stage = 3.0
	if manager_stage != prev_stage:
		SignalBus.manager_stage.emit(manager_stage)

func end_game():
	get_tree().change_scene_to_file("res://bin/ui/start_menu/start_menu.tscn")
