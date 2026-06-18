extends State

var targets : Array
@export var timer : Timer
signal enter_idle
signal exit_idle

func enter():
	enter_idle.emit()
	targets = get_tree().get_nodes_in_group(&"roam_target")
	timer.start()

func _on_idle_time_timeout() -> void:
	var selected_target_index = randi_range(0, targets.size() - 1)
	var selected_target = targets[selected_target_index]
	%Roaming.current_target = selected_target
	%ManagerStates.change_state("roaming")

func exit():
	exit_idle.emit()
