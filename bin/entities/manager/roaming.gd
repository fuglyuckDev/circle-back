extends State

var current_target : Marker3D
@export var manager : CharacterBody3D

func enter():
	pass

func physics_update(_delta: float):
	if current_target:
		get_tree().call_group("enemy", "update_target_location", current_target.transform.origin)

func _on_navigation_agent_3d_target_reached() -> void:
	%ManagerStates.change_state("idle")

func exit():
	current_target = null

func _on_stuck_time_timeout() -> void:
	current_target = %Pos
	%FixTime.start()


func _on_fix_time_timeout() -> void:
	%ManagerStates.change_state("idle")
