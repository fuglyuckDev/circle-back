extends CharacterBody3D



var stamina : float
var default_head_height = 1.431
var crouch_height = default_head_height / 2

@export_category("Camera Settings")
@export var look_sensitivity : float = 0.006
@export var default_fov : float = 75
@export var sprint_fov : float = 90
@export_category("Movement Settings")
@export var SPEED := 5.0
@export var SPRINT_SPEED := 8.0
@export var CROUCH_SPEED := 1.5

func _physics_process(delta: float) -> void:
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		
		if not is_on_floor():
			velocity += get_gravity() * delta
		
		var input_dir := Input.get_vector("left", "right", "forwards", "backwards")
		var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		
		if direction:
			velocity.x = direction.x * SPEED
			velocity.z = direction.z * SPEED
		else:
			velocity.x = move_toward(velocity.x, 0, SPEED)
			velocity.z = move_toward(velocity.z, 0, SPEED)
		
		_sprint(delta)
		_crouch(delta)
		move_and_slide()

func _crouch(delta):
	var tween = create_tween()
	if Input.is_action_pressed("crouch"):
		tween.tween_property(%Head, "position:y", crouch_height, 0.2)
		SPEED = CROUCH_SPEED
	else:
		tween.tween_property(%Head, "position:y", default_head_height, 0.2)

func _sprint(delta) -> void:
	stamina = clamp(stamina, 0.0, 10.0)
	if Input.is_action_pressed("sprint") and stamina > 0.0:
		stamina -= delta*2
		SPEED = SPRINT_SPEED
		var tween = create_tween()
		tween.tween_property(%FirstPersonView, "fov",sprint_fov, 0.2)
	else:
		Input.action_release("sprint")
		SPEED = 3.0
		await get_tree().create_timer(0.0).timeout
		stamina += delta*2
		var tween = create_tween()
		tween.tween_property(%FirstPersonView, "fov",default_fov, 0.2)

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
