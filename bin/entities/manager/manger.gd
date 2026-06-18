extends CharacterBody3D

const SPEED = 2.0
const JUMP_VELOCITY = 4.5

@export var player : CharacterBody3D
@onready var nav_agent := $NavigationAgent3D
@onready var raycast_head = $RaycastHead
@onready var raycast_body = $RaycastBody
@export var turn_speed : float = 8.0
var look_at_target : bool
var is_player_in_range : bool

func _physics_process(delta: float) -> void:
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
	_can_manager_see_player(is_player_in_range)
	move_and_slide()

func update_target_location(target_location):
	nav_agent.target_position = target_location

func _can_manager_see_player(player_in_range):
	print("Checking for player...")
	if player_in_range:
		raycast_body.look_at(player.global_position)
		raycast_head.look_at(player.get_node("Head").global_position)
		print(raycast_body.get_collider())
	else:
		raycast_body.target_position = Vector3.ZERO
		raycast_body.target_position = Vector3.ZERO
	
	

# Currently working on stateless player detection, which then will target player if head / body is visible and change state to persuing.
# Whenever a player is detected, force the state to switch to persuit, emit signal persuing, add player to update_target_location

func _check_if_player_collision(body):
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
