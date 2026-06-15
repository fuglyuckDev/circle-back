extends State

func enter():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _on_interaction_ray_interacted_with(parent_object: Variant) -> void:
	if _get_children_of_type(Marker3D, parent_object):
		var camera_target = _get_children_of_type(Marker3D, parent_object)
		%Controlled.new_camera_target = camera_target
		Input.action_release("interact")
		%CameraState.change_state("Controlled")

func _get_children_of_type(type, object):
	for child in object.get_children():
		if is_instance_of(child, type):
			return child

func physics_update(_delta: float):
	if %FirstPersonView.position != Vector3.ZERO:
		var tween = create_tween()
		tween.tween_property(%FirstPersonView, "position", Vector3.ZERO, 0.5)
