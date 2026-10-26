extends Node3D

var is_viewing_phone := false

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("attack"):
		_handle_attack()
	if event.is_action_pressed("attack_alt"):
		_handle_alt_attack()


func _handle_attack() -> void:
	%AnimationPlayer.play("flashlight")
	%AudioStreamPlayer3D.play()
	%AreaLight3D.visible = !%AreaLight3D.visible
	SignalBus.flashlight_state.emit(%AreaLight3D.visible)
	is_viewing_phone = false
	pass

func _handle_alt_attack() -> void:
	if !is_viewing_phone:
		%AnimationPlayer.play("view_phone")
		is_viewing_phone = true
	else:
		%AnimationPlayer.play("RESET")
		is_viewing_phone = false
	pass
