extends AudioStreamPlayer3D

func _ready() -> void:
	var footsteps = DirAccess.open("res://bin/sounds/player/feets/")
	print(footsteps)
	
