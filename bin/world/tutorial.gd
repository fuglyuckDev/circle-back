extends Node

# First, figure out what input metho they're using

var current_input : String = "KBM"

var kbm_inputs : Array = [{"name": "interact", "value": "E"}, {"name": "flashlight", "value": "Left Mouse Button"}, {"name": "view_phone", "value":"Right Mouse Button"},{"name": "crouch", "value":"CTRL"}]
var controller_inputs : Array = [{"name": "interact", "value": "A/X"}, {"name": "flashlight", "value": "Right Bumper"}, {"name": "view_phone", "value":"Left Bumper"},{"name": "crouch", "value":"B/O"}]
var selected_input : Array = kbm_inputs

var tutorial_stage : int = 0
var tutorial_messages : Array = [{"start":"Press", "end" : "to interact", "type" : "controls"},{"start":"Press", "end" : "to turn on your phone flashlight", "type" : "controls"}, {"start":"Press", "end" : "to view your phone", "type" : "controls"},{"start":"Press", "end" : "to crouch", "type" : "controls"}, {"message": "Interact with screens to push code", "type" : "message"}, {"message": "Interact with desks to hide under them", "type" : "message"}, {"message": "Push code. Don't get caught.", "type" : "message"}, {"message": "Good Luck.", "type" : "message"}]

func _ready() -> void:
	%Timer.start()

func _input(event: InputEvent) -> void:
	if event is InputEventKey or event is InputEventMouseMotion:
		if current_input != "KBM":
			current_input = "KBM"
			selected_input = kbm_inputs
	elif event is InputEventJoypadButton or event is InputEventJoypadMotion:
		if event is InputEventJoypadMotion:
			if abs(event.axis_value) < 0.5:
				return
		if current_input != "controller":
			current_input = "controller"
			selected_input = controller_inputs

func _on_timer_timeout() -> void:
	_construct_tutorial_message(tutorial_stage)
	tutorial_stage += 1

func _construct_tutorial_message(stage:int)-> void:
	if tutorial_stage == tutorial_messages.size() - 1:
		%Timer.stop()
	var tutorial_message = tutorial_messages[stage]
	if tutorial_message["type"] == "controls":
		var message = tutorial_message["start"] + " " + selected_input[stage]["value"] + " " + tutorial_message["end"]
		SignalBus.ui_popup.emit(message)
	else:
		SignalBus.ui_popup.emit(tutorial_message["message"])
