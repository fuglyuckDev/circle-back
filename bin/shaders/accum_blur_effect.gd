@tool
extends CompositorEffect
class_name AccumBlurEffect

## Controls how much of the previous frame's blurred image to blend in. 0 = no blur, 1 = full blur (but full blur is not recommended as it will cause the image to persist indefinitely).
@export_range(0.0, 1.0, 0.001) var alpha: float = 0.0

var rd: RenderingDevice
var shader: RID
var pipeline: RID

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	enabled = true
	rd = RenderingServer.get_rendering_device()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if shader.is_valid():
			rd.free_rid(shader)


func _ensure_shader() -> bool:
	if pipeline.is_valid():
		return true
	if not rd:
		return false

	var shader_file := load("res://bin/shaders/accumulation_shader.glsl") as RDShaderFile
	if not shader_file:
		return false

	var spirv := shader_file.get_spirv()
	shader = rd.shader_create_from_spirv(spirv)
	if not shader.is_valid():
		return false

	pipeline = rd.compute_pipeline_create(shader)
	return pipeline.is_valid()


func _render_callback(_effect_callback_type: int, render_data: RenderData) -> void:
	if not rd or not _ensure_shader():
		return
	if alpha <= 0.0:
		return

	var render_scene_buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if not render_scene_buffers:
		return

	var size := render_scene_buffers.get_internal_size()
	if size.x == 0 or size.y == 0:
		return

	# Create (or retrieve existing) persistent previous-frame texture.
	# create_texture returns the cached RID if it already exists with this name.
	var usage_bits := (
		RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
		| RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
	)
	render_scene_buffers.create_texture(
		&"accum_blur", &"prev_frame",
		RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT,
		usage_bits,
		RenderingDevice.TEXTURE_SAMPLES_1,
		size, 1, 1, false, false
	)

	var x_groups := ceili(float(size.x) / 8.0)
	var y_groups := ceili(float(size.y) / 8.0)

	var push_constant := PackedFloat32Array([size.x, size.y, alpha, 0.0])

	var view_count := render_scene_buffers.get_view_count()
	for view in range(view_count):
		var color_image: RID = render_scene_buffers.get_color_layer(view)
		var prev_image: RID = render_scene_buffers.get_texture_slice(
			&"accum_blur", &"prev_frame", view, 0, 1, 1
		)

		# Uniform for color buffer (binding 0)
		var color_uniform := RDUniform.new()
		color_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		color_uniform.binding = 0
		color_uniform.add_id(color_image)

		# Uniform for previous frame buffer (binding 1)
		var prev_uniform := RDUniform.new()
		prev_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		prev_uniform.binding = 1
		prev_uniform.add_id(prev_image)

		var uniform_set := UniformSetCacheRD.get_cache(shader, 0, [color_uniform, prev_uniform])

		var compute_list := rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
		rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
		rd.compute_list_set_push_constant(compute_list, push_constant.to_byte_array(), push_constant.size() * 4)
		rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
		rd.compute_list_end()
