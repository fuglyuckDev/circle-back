extends CharacterBody3D

var SPEED = 2.0
const JUMP_VELOCITY = 4.5

@export var PERSUE_SPEED : float = 6.5
@export var WALK_SPEED : float = 2.0
@export var player : CharacterBody3D
@onready var nav_agent := $NavigationAgent3D
@onready var raycast_head = $RaycastHead
@onready var raycast_body = $RaycastBody
@export var turn_speed : float = 16.0
var look_at_target : bool
var is_player_in_range : bool
var player_last_known_pos : Vector3

signal player_position(player_pos:Vector3)
signal search_position(search_pos:Vector3)
signal collided_with_player(manager)

func _physics_process(delta: float) -> void:
	if %ManagerStates.current_state == %Persuing or %ManagerStates.current_state == %Searching:
		SPEED = PERSUE_SPEED
	else:
		SPEED = WALK_SPEED
	
	if not is_on_floor():
		velocity += get_gravity() * delta # Have the enemy fall if it's in the air :o
	var current_location = global_transform.origin # Enemy's current location
	var next_location = nav_agent.get_next_path_position() # Calls the nav agent looking for the next path position, in this case, the function below (update_target_location) runs every physics tick to send the player's position to the nav agent
	var new_velocity = (next_location - current_location).normalized() * SPEED # next_location - current_location to get direction of player, normalized keeps the length to 1. * SPEED for the speed of the bastard.
	
	velocity = velocity.move_toward(new_velocity, .25) # Honestly not sure what the .25 is. Docs don't help either lol

	var move_dir := Vector3(velocity.x, 0, velocity.z)
	if look_at_target:
		if move_dir.length_squared() > 0.01:
			var target_transform = transform.looking_at(global_position - move_dir, Vector3.UP)
			global_transform.basis = global_transform.basis.slerp(target_transform.basis, turn_speed * delta)
	if %ManagerStates.current_state == %Idle:
		%manager_model.manager_current_speed = 0
	else:
		%manager_model.manager_current_speed = Vector2(velocity.x,velocity.y).length()
	%manager_model.manager_idle_speed = WALK_SPEED
	%manager_model.manager_persue_speed = PERSUE_SPEED
	_can_manager_see_player(is_player_in_range)
	move_and_slide()

func update_target_location(target_location):
	nav_agent.target_position = target_location


func _over_persue():
	if %ManagerStates.current_state == %Persuing:
		if %OverPersue.is_stopped():
			%OverPersue.start(2.0)
		else:
			if %OverPersue.time_left > 0.01:
				player_position.emit(player.transform.origin)
				player_last_known_pos = player.transform.origin
			else:
				print("Player last known pos: ", player_last_known_pos)
				%ManagerStates.change_state("Searching")
				search_position.emit(player_last_known_pos)

func _can_manager_see_player(player_in_range):
	if player_in_range:
		raycast_body.target_position = to_local(player.global_position)
		raycast_head.target_position = to_local(player.get_node("Head").global_position)
		raycast_body.target_position.y = raycast_body.target_position.y - 0.9
		raycast_head.target_position.y = raycast_head.target_position.y - 1.8
		if _check_if_player_collision(raycast_body.get_collider()) or _check_if_player_collision(raycast_head.get_collider()):
			if %ManagerStates.current_state != %Persuing:
				%ManagerStates.change_state("Persuing")
			else:
				%OverPersue.stop()
				player_position.emit(player.transform.origin)
		else:
			_over_persue()
	else:
		_over_persue()

# Currently working on stateless player detection, which then will target player if head / body is visible and change state to persuing.
# Whenever a player is detected, force the state to switch to persuit, emit signal persuing, add player to update_target_location

func _check_if_player_collision(body):
	if body:
		var body_groups = body.get_groups()
		if body_groups.has(&"player"):
			return true

func _on_idle_enter_idle() -> void:
	look_at_target = false

func _on_idle_exit_idle() -> void:
	look_at_target = true

func _on_area_3d_body_entered(body: Node3D) -> void:
	if _check_if_player_collision(body):
		is_player_in_range = true

func _on_area_3d_body_exited(body: Node3D) -> void:
	if _check_if_player_collision(body):
		is_player_in_range = false


func _on_kill_radius_body_entered(body: Node3D) -> void:
	if body.get_groups().get(0) == &"player":
		collided_with_player.emit(%manager_model.get_marker())
		%manager_model.play_animtaion()

func _on_light_flicker_body_entered(body: Node3D) -> void:
	print(body)
	if body.get_parent().get_groups().get(0) == &"lights":
		body.get_parent().flicker_light()
