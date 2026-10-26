extends Button

func _on_pressed() -> void:
	%PanelContainer.visible = !%PanelContainer.visible


func _on_close_options_pressed() -> void:
	grab_focus()
