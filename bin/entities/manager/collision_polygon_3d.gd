extends CollisionPolygon3D

var viewcone_normal = [Vector2(0.0, 0.0), Vector2(5.0, 9.0), Vector2(-5.0, 9.0)]
var viewcone_flashlight = [Vector2(0.0, 0.0), Vector2(8.0, 14.0), Vector2(-8.0, 14.0)]

func _ready() -> void:
	SignalBus.flashlight_state.connect(_on_flashlight_change)

func _on_flashlight_change(value:bool) -> void:
	if value:
		self.polygon = viewcone_flashlight
	else:
		self.polygon = viewcone_normal
