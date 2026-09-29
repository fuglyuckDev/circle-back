extends Node3D

@export var can_leave := false

func _ready() -> void:
	%ExitSign.get_active_material(0).emission_enabled = false
	%ExitSign.get_children()[0].visible = false

func _process(_delta: float) -> void:
	if !can_leave:
		if GameState.completed_tasks == GameState.useable_monitors:
			can_leave = true
			open_door()


func open_door():
	SignalBus.ui_popup.emit("Leave. Now.")
	%ExitSign.get_active_material(0).emission_enabled = true
	%ExitSign.get_children()[0].visible = true
	self.add_to_group(&"interactable")

func interact():
	GameState.end_game()
