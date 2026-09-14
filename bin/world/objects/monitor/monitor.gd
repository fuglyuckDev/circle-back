extends Node3D

func _coin_flip():
	var random_to_one = randi_range(1, 2)
	if random_to_one % 2 == 0:
		return true
	else:
		return false 

func _ready() -> void:
	if GameState.useable_monitors > 0:
		if _coin_flip():
			GameState.useable_monitors = GameState.useable_monitors - 1
			_generate_useable_monitor()

func interact() -> void:
	%Complete_timer.start()
	%MonitorScreen.interacted()
	%Typing.play()

func _generate_useable_monitor() -> void:
	add_to_group("interactable")
	%Screen_on.visible = true

func _on_complete_timer_timeout() -> void:
	remove_from_group("interactable")
	%Screen_on.visible = false
	GameState.completed_tasks = GameState.completed_tasks + 1
	SignalBus.task_complete.emit()
	SignalBus.unmount_user.emit()

# Added a comment for git push
# Hello you sneaky dog how can you read this >:(
