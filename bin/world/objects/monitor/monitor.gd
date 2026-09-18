extends Node3D

func interact() -> void:
	%Complete_timer.start()
	%MonitorScreen.interacted()
	%Typing.play()

func generate_useable_monitor() -> void:
	add_to_group("interactable")
	%Screen_on.visible = true
	GameState.useable_monitors = GameState.useable_monitors + 1

func _on_complete_timer_timeout() -> void:
	remove_from_group("interactable")
	%Screen_on.visible = false
	GameState.completed_tasks = GameState.completed_tasks + 1
	SignalBus.task_complete.emit()
	SignalBus.unmount_user.emit()
