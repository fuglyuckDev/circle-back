extends Button

@onready var config = ConfigFile.new()

func _on_pressed() -> void:
	config.set_value("options", "mouse_sensitivity", %MouseSensitivitySlider.value)
	config.set_value("options", "controller_sensitivity", %ControllerSensitivitySlider.value)
	config.set_value("options", "motion_blur", %MotionBlurSlider.value)
	
	config.save("user://options.cfg")
