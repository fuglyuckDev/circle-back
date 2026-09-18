extends Node3D

@onready var player := $Player
var desk_groups : Array

# As of right now everything is on collision layer / mask 1
# Maybe add raycasting to collision layer 2
# Add player to collision layer 2
# add obscuring geometry to layer 2
# Make sure glass is only layer 1

# Monitor spawn logic now lives here.
# Create Desk Groups

# One monitor per desk group.
# Random position inside desk group

func _ready() -> void:
	desk_groups = %Desks.get_children(false)
	for deskGroup in desk_groups:
		var desks = deskGroup.get_children(false)
		var selected_desk_for_group = _get_random_desk(desks)
		selected_desk_for_group.select()

func _get_random_desk(array: Array) -> Node3D:
	var array_size = array.size()
	var random_number = randi() % array_size
	return array[random_number]

func _exit_tree() -> void:
	GameState.useable_monitors = 0
	GameState.completed_tasks = 0
