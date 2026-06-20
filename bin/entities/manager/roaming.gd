extends State

var current_target : Marker3D

func enter():
	print("Roaming...")

func physics_update(_delta: float):
	if current_target:
		get_tree().call_group("enemy", "update_target_location", current_target.transform.origin)

func _on_navigation_agent_3d_target_reached() -> void:
	%ManagerStates.change_state("idle")

func exit():
	current_target = null
