extends Node3D

var messages := ["Good job, keep going.", "Nice work, keep it up.", "Well done, on to the next.", "Niceeeee, keep going man, you got this.", "wtf nice job", "Ugh, who'd even write that code? gj.", "lmao that was mine, please ignore the giga nested for loop :D"]
var rng = RandomNumberGenerator.new()

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
	
	var random_message_idx = rng.randi_range(0, messages.size() - 1)
	if GameState.completed_tasks == GameState.useable_monitors - 1:
		SignalBus.ui_popup.emit("Sick, one left, good luck.")
	else:
		SignalBus.ui_popup.emit(messages[random_message_idx])
