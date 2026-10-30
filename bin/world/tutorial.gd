extends Node

# First, figure out what input metho they're using

var current_input : String = "KBM"

# Add some intro "lore" to the tutorial: 
# "dude you fell asleep at your desk again didn't you?"
# "You missed so much..."
# "The manager has gone full AI psychosis, you've got to get out of there!"
# "Before you go, can you push all of our code?"
# "Y'know, before she set's ChapGTC on it?"
# "Bro just push the code by pressing {} to interact with the monitors"
# "Make sure she doesn't see you..."
# "Press {} to crouch if you have to."
# "Hiding under desks work too, just interact with them"
# "Just DON'T get caught, she'll convert you too..."
# "Alright i'm watching on the CCTV, get it done and get out..."
# "Good luck."

var kbm_inputs : Array = [{"name": "interact", "value": "E"}, {"name": "flashlight", "value": "Left Mouse Button"}, {"name": "view_phone", "value":"Right Mouse Button"},{"name": "crouch", "value":"CTRL"}]
var controller_inputs : Array = [{"name": "interact", "value": "A/X"}, {"name": "flashlight", "value": "Right Bumper"}, {"name": "view_phone", "value":"Left Bumper"},{"name": "crouch", "value":"B/O"}]
var selected_input : Array = kbm_inputs

var tutorial_stage : int = 0
var tutorial_messages : Array = [{"message": "Dude, you fell asleep at your desk again, didn't you?", "type": "message"},{"message": "You missed so much...", "type": "message"},{"message": "The manager has gone full AI psychosis, you've got to get out of there!", "type": "message"},{"message": "Before you go, can you push all of our code?", "type": "message"},{"message": "Y'know, before she set's ChapGTC on it?", "type": "message"},{"start":"Bro just push the code by pressing", "end" : ", yknow, to interact with things?", "type" : "controls", "hint": "interact"},{"message": "Make sure she doesn't see you...", "type": "message"},{"start":"Press", "end" : "to turn on your phone flashlight", "type" : "controls", "hint": "flashlight"}, {"start":"Press", "end" : "to view your phone", "type" : "controls", "hint": "view_phone"},{"start":"Press", "end" : "to crouch, y'know, if you have to...", "type" : "controls", "hint": "crouch"}, {"message": "Hiding under desks work too, just interact with them", "type" : "message"}, {"message": "Just DON'T get caught, she'll convert you too...", "type" : "message"},{"message": "Alright i'm watching on the CCTV, get it done and get out...", "type": "message"}, {"message": "Good Luck.", "type" : "message"}]

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
		var get_hint = selected_input.filter(func(object): return object["name"] == tutorial_message["hint"])
		print(get_hint)
		var message = tutorial_message["start"] + " " + get_hint[0]["value"] + " " + tutorial_message["end"]
		SignalBus.ui_popup.emit(message)
	else:
		SignalBus.ui_popup.emit(tutorial_message["message"])
