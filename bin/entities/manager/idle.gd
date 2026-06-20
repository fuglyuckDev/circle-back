extends State

var targets : Array
@export var timer : Timer
signal enter_idle
signal exit_idle

func enter():
	print("Idle")
	enter_idle.emit()
	targets = get_tree().get_nodes_in_group(&"roam_target")
	timer.start()

func _on_idle_time_timeout() -> void:
	var selected_target_index = randi_range(0, targets.size() - 1)
	var selected_target = targets[selected_target_index]
	%Roaming.current_target = selected_target
	%ManagerStates.change_state("roaming")

func exit():
	timer.stop()
	exit_idle.emit()

# Currently greyboxing.
# How about a procedural desk? Monitors, mice, keyboards, tat, things like that all "on ready" choose their location with predefined locations?
# This just means I don't have to manually create desks and their clutter.
# I can greybox different assets using CSGShapes.
# Create a clutter library and random clutter locations too.
# This just means each playthrough is unique :D
# Or if I want manual control, I can use @export to drop in specific assets and select their location :D
# Once done, see if this loads instantly or takes some time to do. If it's too much time, will need a loader:
# ------------------------ WARNING - OVER-ENGINEERING BELOW --------------------------------------
# When the scene enters the tree, state will be "loading", this places everything down.
# When everything is placed, switch state to "done" state.
# "Done" state emits a signal to a loading signalBus.
# All desks are in a "Desks" group.
# Signalbus on ready, gets all desks in the group and listens for a signal from each of them.
# Signal counter starts at 0, each signal increments to n desks.
# if n = deskArray.length() or something, then emit "done" to change scene from loading to the actual game :D
