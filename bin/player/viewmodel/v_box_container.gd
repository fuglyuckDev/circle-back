extends VBoxContainer

var message_scene = preload("res://bin/player/viewmodel/message.tscn")

func _ready() -> void:
	SignalBus.ui_popup.connect(_on_message_recieve)

func _on_message_recieve(message:String):
	var new_instace = message_scene.instantiate()
	new_instace.text = message
	add_child(new_instace)
