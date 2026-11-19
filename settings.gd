extends Node

var current_control_scheme := "KBM"

# Controls
var mouse_sensitivity : float = 0.006
var joypad_sensitivity : float = 0.03

# Accessibility
var motion_blur : float = 0.98

func _ready() -> void:
	SignalBus.set_control_scheme.connect(_on_control_scheme_change)

func _on_control_scheme_change(value:String) -> void:
	current_control_scheme = value
