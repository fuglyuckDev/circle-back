extends State

var new_camera_target : Marker3D
var initial_position := Vector3.ZERO
var t = 0.0

func _ready() -> void:
	SignalBus.unmount_user.connect(_unmount_user)

func enter():
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("Controlled input, camera target: ", new_camera_target)

func update(delta) -> void:
	t += delta * 4.0
	if new_camera_target != null:
		var tween = create_tween()
		tween.parallel().tween_property(%FirstPersonView, "global_position", new_camera_target.global_position, 0.5)
		tween.parallel().tween_property(%FirstPersonView, "global_rotation", new_camera_target.global_rotation, 0.5)

func exit():
	new_camera_target = null
	SignalBus.can_interact.emit(true)

func _unmount_user() -> void:
	%CameraState.change_state("FirstPerson")
