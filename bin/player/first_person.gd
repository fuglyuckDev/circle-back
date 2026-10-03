extends State

var returned_camera_pos := false

@export var player : CharacterBody3D

@export_category("Camera Movement")
@export_group("Head Bob")
@export var hb_amplitude := 1.0
@export var hb_freq := 1.0
@export_group("Screenshake")
## How far the screen shakes, higher = further
@export var ss_random_strength := 30.0
@export var shake_fade := 5.0

var rng = RandomNumberGenerator.new()
var shake_strength := 0.0

var hb_time : float
var ss_time : float
var ss_playing = false
var can_play_foosteps := true

var start_head_position = null

var persuit := false

func enter():
	start_head_position = %FirstPersonView.position
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	%Feets.play()
	SignalBus.jumpscare_screenshake.connect(_on_start_jumpscare)
	SignalBus.persuit.connect(_on_enter_persuit)
	SignalBus.exit_persuit.connect(_on_exit_persuit)

func _on_enter_persuit() -> void:
	persuit = true

func _on_exit_persuit() -> void:
	persuit = false

func _head_bob(delta: float) -> void:
	hb_time += delta
	if player.velocity.length() > 0.0 and player.is_on_floor():
		var sine = sin(hb_time * (hb_freq * player.velocity.length()) ) * hb_amplitude
		%FirstPersonView.position.y = %FirstPersonView.position.y + sine
		play_footstep(clampf(remap(sine, -0.003, 0.004, 0.0, 1.0),0.0,1.0))
	elif player.is_on_floor():
		var tween = create_tween()
		tween.tween_property(%FirstPersonView, "position:y", 0.0, 0.2)

func play_footstep(headbob_value):
	if headbob_value == 0.0:
		if can_play_foosteps:
			%Feets.play()
			can_play_foosteps = false
	else:
		can_play_foosteps = true

func apply_shake():
	shake_strength = ss_random_strength

func _on_start_jumpscare():
	apply_shake()

func random_offset() -> Vector2:
	return Vector2(rng.randf_range(-shake_strength, shake_strength),rng.randf_range(-shake_strength, shake_strength),)

func _on_interaction_ray_interacted_with(parent_object: Variant) -> void:
	if not persuit:
		_move_camera(parent_object)
	else:
		SignalBus.ui_popup.emit("Now is not the time.")

func _get_children_of_type(type, object):
	for child in object.get_children():
		if is_instance_of(child, type):
			return child
		else:
			_get_children_of_type(type, child)

func _move_camera(parent_object: Variant):
	if _get_children_of_type(Marker3D, parent_object):
		var camera_target = _get_children_of_type(Marker3D, parent_object)
		_start_camera_move(camera_target)

func _start_camera_move(camera_target):
	%Controlled.new_camera_target = camera_target
	Input.action_release("interact")
	%CameraState.change_state("Controlled")

func start_player_death(camera_target) -> void:
	_start_camera_move(camera_target)

func physics_update(delta: float):
	if %FirstPersonView.position != Vector3.ZERO and returned_camera_pos == false:
		var tween = create_tween()
		tween.parallel().tween_property(%FirstPersonView, "position", Vector3.ZERO, 0.5)
		tween.parallel().tween_property(%FirstPersonView, "rotation", Vector3.ZERO, 0.5)
		returned_camera_pos = true
	else:
		returned_camera_pos = true
	_head_bob(delta)
	if shake_strength > 0:
		shake_strength = lerpf(shake_strength, 0, shake_fade * delta)
		%FirstPersonView.v_offset = random_offset().y
		%FirstPersonView.h_offset = random_offset().x


func exit():
	returned_camera_pos = false
