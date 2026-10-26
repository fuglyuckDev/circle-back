extends HSlider


func _on_value_changed(value: float) -> void:
	Settings.joypad_sensitivity = value
