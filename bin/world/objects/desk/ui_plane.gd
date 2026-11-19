extends MeshInstance3D

func _physics_process(delta: float) -> void:
	if GameState.player_camera:
		if self.get_parent().is_targeted:
			if !self.visible:
				self.visible = true
			self.look_at(GameState.player_camera.global_position)
		else:
			self.visible = false
