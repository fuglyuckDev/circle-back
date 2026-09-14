extends State

var returned_camera_pos := false

@export var player : CharacterBody3D

@export_category("Head bob strength")
@export var amplitude := 1.0
@export var freq := 1.0
var time : float
var can_play_foosteps := true

func _head_bob(delta: float) -> void:
	time += delta
	if player.velocity.length() > 0.0 and player.is_on_floor():
		var sine = sin(time * (freq * player.velocity.length()) ) * amplitude
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

func enter():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	%Feets.play()

func _on_interaction_ray_interacted_with(parent_object: Variant) -> void:
	_move_camera(parent_object)

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

func exit():
	returned_camera_pos = false
