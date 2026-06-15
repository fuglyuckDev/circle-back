extends Node

# Create class with global scope :D
class_name State

# Ref state machine:
var state_machine: StateMachine
# Create custom primitive virtual methods that child state can override

# Init - quite like _ready()
func enter():
	pass

# Cleanup
func exit():
	pass

# Alternate to _process()
func update(_delta: float):
	pass

# Alternate to _physics_process
func physics_update(_delta: float):
	pass

# Alternate to _unhandled_input ?
func handle_input(_event: InputEvent):
	pass
