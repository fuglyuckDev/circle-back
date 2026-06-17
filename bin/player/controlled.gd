extends State

var new_camera_target : Marker3D
var initial_position := Vector3.ZERO
var t = 0.0

func enter():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func update(delta) -> void:
	t += delta * 4.0
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		%CameraState.change_state("FirstPerson")
	if new_camera_target:
		var tween = create_tween()
		tween.parallel().tween_property(%FirstPersonView, "global_position", new_camera_target.global_position, 0.5)
		tween.parallel().tween_property(%FirstPersonView, "global_rotation", new_camera_target.global_rotation, 0.5)

func exit():
	new_camera_target = null
