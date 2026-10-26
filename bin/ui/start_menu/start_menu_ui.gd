extends Control

@export var buttons : Array[Button]
var config = ConfigFile.new()

func _ready() -> void:
	_get_buttons()
	_get_user_options()
	%Ambience.play()

func _get_buttons():
	for child in buttons:
		if child is Button:
			child.mouse_entered.connect(_on_button_hovered)
			child.focus_entered.connect(_on_button_hovered)
			child.button_down.connect(_on_button_pressed)

func _on_button_hovered():
	%ButtonHover.play()

func _on_button_pressed():
	%ButtonPressed.play()

func _get_user_options() -> void:
	var options = config.load("user://options.cfg")
	if options != OK:
		return
	else:
		for config_options in config.get_sections():
			%MouseSensitivitySlider.value = config.get_value(config_options, "mouse_sensitivity")
			%ControllerSensitivitySlider.value = config.get_value(config_options, "controller_sensitivity")
			%MotionBlurSlider.value = config.get_value(config_options, "motion_blur")
