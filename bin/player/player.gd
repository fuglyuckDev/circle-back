extends CharacterBody3D

var stamina : float
var default_head_height = 1.431
var crouch_height = default_head_height / 2
var is_hiding := false
var is_persued := false
var can_interact := true

@export_category("Camera Settings")
@export var look_sensitivity : float = 0.006
@export var joypad_sensitivity : float = 0.03
@export var default_fov : float = 75
@export var sprint_fov : float = 90
@export_category("Movement Settings")
@export var SPEED := 5.0
@export var SPRINT_SPEED := 8.0
@export var CROUCH_SPEED := 1.5
@export_category("Enemy")
@export var enemy : CharacterBody3D
@export_category("Sting Settings")
@export var MAX_DISTANCE : float = 25.0
@export var MIN_DB = -80.0
@export var MAX_DB = -30.0
@export var MAX_BLUR = 0.98
@export var MIN_BLUR = 0.9

func _ready() -> void:
	SignalBus.enemy_enter_view.connect(_on_manager_in_view)
	SignalBus.persuit.connect(_on_manager_persuit)
	SignalBus.exit_persuit.connect(_on_manager_exit_persuit)
	SignalBus.is_hiding.connect(_on_is_hiding)
	SignalBus.manager_stage.connect(_on_manager_stage_change)
	SignalBus.can_interact.connect(_on_can_interact)

func _process(_delta) -> void:
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		var h_look:float = Input.get_axis("l_right", "l_left")
		rotate_y(h_look * joypad_sensitivity)
		var v_look:float = Input.get_axis("l_down", "l_up")
		%Head.rotate_x(v_look * look_sensitivity)
		%Head.rotation.x = clamp(%Head.rotation.x, deg_to_rad(-90), deg_to_rad(90))

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

func _crouch(_delta):
	var tween = create_tween()
	if Input.is_action_pressed("crouch"):
		tween.tween_property(%Head, "position:y", crouch_height, 0.2)
		SPEED = CROUCH_SPEED
	else:
		tween.tween_property(%Head, "position:y", default_head_height, 0.2)

func _sprint(_delta) -> void:
	stamina = clamp(stamina, 0.0, 10.0)
	if Input.is_action_pressed("sprint"):
		SPEED = SPRINT_SPEED
		var tween = create_tween()
		tween.tween_property(%FirstPersonView, "fov",sprint_fov, 0.2)
	else:
		Input.action_release("sprint")
		SPEED = 3.0
		var tween = create_tween()
		tween.tween_property(%FirstPersonView, "fov",default_fov, 0.2)

func _unhandled_input(event: InputEvent) -> void:
	#Capture mouse events if clicked, exit with esc
	#if event is InputEventMouseButton:
		#Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if event.is_action_pressed("ui_cancel"):
		SignalBus.ui_popup.emit("There is no escape.")
	#Read mouseinput and multiply by look sensitivity to move camera
	#Left / right rotates body left and right
	#up / down rotates camera
	if event.is_action_pressed("test"):
		SignalBus.jumpscare_screenshake.emit()
	if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
		if event.is_action_pressed("interact"):
			if is_hiding:
				revert_first_person()
				revert_hiding()
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		if event is InputEventMouseMotion:
			rotate_y(-event.relative.x * look_sensitivity)
			%Head.rotate_x(-event.relative.y * look_sensitivity)
			%Head.rotation.x = clamp(%Head.rotation.x, deg_to_rad(-90), deg_to_rad(90))
	pass

func revert_first_person() -> void:
	%CameraState.change_state("FirstPerson")

func revert_hiding() -> void:
	set_collision_layer_value(1, true)
	set_collision_mask_value(1, true)
	is_hiding = false

func toggle_blur_effect(value:float) -> void:
	for effect in %FirstPersonView.compositor.compositor_effects:
		if effect is AccumBlurEffect:
			effect.alpha = value
			return

func _on_sting_timer_timeout() -> void:
	toggle_blur_effect(0.0)

func _on_manger_collided_with_player(marker) -> void:
	if %CameraState.current_state == %Controlled:
		revert_first_person()
	%FirstPerson.start_player_death(marker)

func _on_manager_persuit() -> void:
	is_persued = true
	if !%Sting.playing and %StingTimer.is_stopped():
		%Sting.stream = preload("res://bin/sounds/player/horror-sting.mp3")
		%Sting.play()
		%StingTimer.start()
		toggle_blur_effect(MAX_BLUR)
		SignalBus.jumpscare_screenshake.emit()

func _on_manager_exit_persuit() -> void:
	is_persued = false

func _on_manager_in_view(enemy_position:Vector3) -> void:
	var distance_to_enemy = self.global_position.distance_to(enemy_position)
	var distance_to_db = clampf(remap(distance_to_enemy, 0.0, MAX_DISTANCE, MAX_DB ,MIN_DB), MIN_DB, MAX_DB) 
	var distance_to_intensity = clampf(remap(distance_to_enemy, 0.0, MAX_DISTANCE, MAX_BLUR, MIN_BLUR ), MIN_BLUR, MAX_BLUR)
	if %StingTimer.is_stopped() and distance_to_enemy < MAX_DISTANCE:
		%Sting.volume_db = distance_to_db
		%Sting.stream = preload("res://bin/sounds/player/horror-stinger.mp3")
		%Sting.play()
		%StingTimer.start()
		toggle_blur_effect(distance_to_intensity)
		SignalBus.jumpscare_screenshake.emit()

func _on_is_hiding(value) -> void:
	is_hiding = value
	if !is_persued:
		set_collision_layer_value(1, false)
		set_collision_mask_value(1, false)

func _on_manager_stage_change(stage:float) -> void:
	print(stage)
	if stage >= 1.0:
		Input.start_joy_vibration(0.0,0.5,0.5,5.0)
		%Sting.stream = preload("res://bin/sounds/player/manager_scream.mp3")
		%Sting.play()
		%StingTimer.start()
		toggle_blur_effect(MAX_BLUR)
		SignalBus.jumpscare_screenshake.emit()

func _on_can_interact(value:bool) -> void:
	can_interact = value
