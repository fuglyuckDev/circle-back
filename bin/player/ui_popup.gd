extends Button

@export var text_value := ""
@export var alert_icon := preload("res://bin/ui/alerts/info_icon.png")

func _ready() -> void:
	text = text_value
	icon = alert_icon

func _on_alive_time_timeout() -> void:
	queue_free()
