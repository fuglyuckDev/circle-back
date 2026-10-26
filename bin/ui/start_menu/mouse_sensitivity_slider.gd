extends HSlider

func _on_options_pressed() -> void:
	grab_focus()

func _on_value_changed(value: float) -> void:
	Settings.mouse_sensitivity = value
