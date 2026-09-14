extends Button

@onready var office = preload("res://bin/world/office.tscn")

func _on_button_down() -> void:
	get_tree().change_scene_to_packed(office)
