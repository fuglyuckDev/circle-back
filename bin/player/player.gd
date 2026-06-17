extends CharacterBody3D


var SPEED = 5.0
const JUMP_VELOCITY = 4.5
@export var look_sensitivity : float = 0.006
var stamina : float

func _physics_process(delta: float) -> void:
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		# Add the gravity.
		if not is_on_floor():
			velocity += get_gravity() * delta

		# Get the input direction and handle the movement/deceleration.
		# As good practice, you should replace UI actions with custom gameplay actions.
		var input_dir := Input.get_vector("left", "right", "forwards", "backwards")
		var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		if direction:
			velocity.x = direction.x * SPEED
			velocity.z = direction.z * SPEED
		else:
			velocity.x = move_toward(velocity.x, 0, SPEED)
			velocity.z = move_toward(velocity.z, 0, SPEED)
		_sprint(delta)
		move_and_slide()

func _sprint(delta) -> void:
	stamina = clamp(stamina, 0.0, 10.0)
	if Input.is_action_pressed("sprint") and stamina > 0.0:
		stamina -= delta*2
		SPEED = 8.0
	else:
		Input.action_release("sprint")
		SPEED = 5.0
		await get_tree().create_timer(1.0).timeout
		stamina += delta*2

func _unhandled_input(event: InputEvent) -> void:
	#Capture mouse events if clicked, exit with esc
	if event is InputEventMouseButton:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	elif event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	#Read mouseinput and multiply by look sensitivity to move camera
	#Left / right rotates body left and right
	#up / down rotates camera
	
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		if event is InputEventMouseMotion:
			rotate_y(-event.relative.x * look_sensitivity)
			%FirstPersonView.rotate_x(-event.relative.y * look_sensitivity)
			%FirstPersonView.rotation.x = clamp(%FirstPersonView.rotation.x, deg_to_rad(-90), deg_to_rad(90))
	pass
