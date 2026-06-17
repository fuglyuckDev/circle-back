extends CharacterBody3D


const SPEED = 2.0
const JUMP_VELOCITY = 4.5

@export var player : CharacterBody3D
@onready var nav_agent := $NavigationAgent3D

func _physics_process(delta: float) -> void:
	look_at(player.global_position)
	if not is_on_floor():
		velocity += get_gravity() * delta
	
	var direction := player.global_position - self.global_position
	clamp(velocity, Vector3.ZERO, Vector3(SPEED,SPEED,SPEED))
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()

# use this video to help with navigation: https://www.youtube.com/watch?v=-juhGgA076E
# use the video combined with states to get some complex navigation behaviour:
# idle state would be when it's waiting at a target position.
# roaming state would have it move to set places on the map.
# chase state will have it chase the player :smile:
