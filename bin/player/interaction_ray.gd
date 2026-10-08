extends RayCast3D

signal interacted_with(parent_object)

@export var player : CharacterBody3D

func _unhandled_input(_event: InputEvent) -> void:
	if Input.is_action_just_pressed("interact") and player.can_interact:
		var interaction_target = self.get_collider()
		if interaction_target:
			var parent = interaction_target.get_parent()
			var parent_groups = parent.get_groups()
			if !parent_groups.is_empty() and parent_groups[0] == &"interactable":
				parent.interact()
				interacted_with.emit(parent)
				SignalBus.can_interact.emit(false)
