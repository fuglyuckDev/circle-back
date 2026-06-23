extends Node3D

var manager_current_speed : float
var manager_idle_speed : float
var manager_persue_speed : float

func _physics_process(delta: float) -> void:
	_handle_walk(manager_current_speed, manager_idle_speed)

func _handle_walk(current, walk):
	var normalised_speed = current / walk
	%AnimationTree["parameters/BlendSpace1D/blend_position"] = normalised_speed
	if normalised_speed > 1.0:
		%AnimationTree["parameters/TimeScale/scale"] = 3.0
	else:
		%AnimationTree["parameters/TimeScale/scale"] = 1.0

func get_marker():
	return %CameraPoint

func play_animtaion():
	%AnimationTree["parameters/Kill/request"] = AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE
