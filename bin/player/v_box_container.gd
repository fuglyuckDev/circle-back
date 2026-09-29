extends VBoxContainer

func _ready() -> void:
	SignalBus.ui_popup.connect(_on_popup)

func _on_popup(text):
	var new_child = preload("res://bin/player/ui_popup.tscn")
	var instanced_child = new_child.instantiate()
	instanced_child.text_value = text
	add_child(instanced_child)
