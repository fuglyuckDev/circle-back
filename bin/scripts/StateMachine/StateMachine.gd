extends Node

class_name StateMachine

@export var initial_state: State
var current_state: State
var states: Dictionary = {}

func _ready() -> void:
	# Register all child states:
	for child in get_children():
		if child is State:
			states[child.name.to_lower()] = child
			child.state_machine = self
	if initial_state:
		change_state(initial_state.name.to_lower())

func _process(delta: float) -> void:
	if current_state:
		current_state.update(delta)

func _physics_process(delta: float) -> void:
	if current_state:
		current_state.physics_update(delta)

func _input(event: InputEvent) -> void:
	if current_state:
		current_state.handle_input(event)

func change_state(new_state_name: String) -> void:
	# If there's already a current state, exit it
	if current_state:
		current_state.exit()
	
	# Then, with the passed property of state name, change to that state
	current_state = states.get(new_state_name.to_lower())
	
	# Start state "_ready" logic
	if current_state:
		current_state.enter()
