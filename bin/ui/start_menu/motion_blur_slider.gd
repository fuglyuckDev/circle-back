extends HSlider


func _on_value_changed(value: float) -> void:
	Settings.motion_blur = value
