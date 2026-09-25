extends Control

func _ready() -> void:
	var buttons = _get_buttons()
	%Ambience.play()

func _get_buttons():
	for child in get_children():
		if child is Button:
			child.mouse_entered.connect(_on_button_hovered)
			child.button_down.connect(_on_button_pressed)

func _on_button_hovered():
	%ButtonHover.play()

func _on_button_pressed():
	%ButtonPressed.play()
