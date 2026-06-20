extends State

var new_search_pos : Vector3

func enter():
	print("Searching...")

func physics_update(_delta: float):
	get_tree().call_group("enemy", "update_target_location", new_search_pos)

func _on_navigation_agent_3d_target_reached() -> void:
	print("Target Reached")
	%ManagerStates.change_state("Idle")

func _on_manger_search_position(search_pos: Vector3) -> void:
	new_search_pos = search_pos
