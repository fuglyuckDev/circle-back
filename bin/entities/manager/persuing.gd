extends State

var current_target_location : Vector3

func enter():
	print("Chasing")

func physics_update(_delta: float):
	get_tree().call_group("enemy", "update_target_location", current_target_location)


func _on_manger_player_position(player_pos: Vector3) -> void:
	current_target_location = player_pos


func _on_navigation_agent_3d_target_reached() -> void:
	%ManagerStates.change_state("Idle")

func exit():
	current_target_location = Vector3.ZERO
