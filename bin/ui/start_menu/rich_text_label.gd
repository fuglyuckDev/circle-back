extends RichTextLabel

var label_text_value : String
@onready var slider = get_parent().get_child(1)

func _ready() -> void:
	label_text_value = str(slider.value)
	self.text = label_text_value

func _on_h_slider_value_changed(value: float) -> void:
	label_text_value = str(value)
	self.text = label_text_value
