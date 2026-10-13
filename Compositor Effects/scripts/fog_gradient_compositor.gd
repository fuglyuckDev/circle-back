@tool
class_name FogGradientCompositorEffect
extends CompositorEffect

enum FogPreset {
	SUNSET_ATMOSPHERE,
	CYBERPUNK_NEON_HAZE,
	DEEP_OCEAN_MIST,
	CUSTOM
}

@export_enum("Sunset Atmosphere", "Cyberpunk Neon Haze", "Deep Ocean Mist", "Custom") var fog_preset: int = FogPreset.SUNSET_ATMOSPHERE:
	set(value):
		fog_preset = value
		_apply_preset()

## Atmospheric gradient fog density scaling factor.
@export_range(0.1, 5.0, 0.1) var fog_density: float = 1.2
## Distance in meters where fog begins.
@export_range(0.0, 50.0, 0.5) var fog_start: float = 2.0
## Distance in meters where fog reaches full opacity.
@export_range(5.0, 200.0, 5.0) var fog_end: float = 50.0
## Vertical height falloff power.
@export_range(0.1, 3.0, 0.1) var height_falloff: float = 1.0
@export_range(0.01, 10.0, 0.05) var z_near: float = 0.1
@export_range(10.0, 1000.0, 10.0) var z_far: float = 100.0
@export_color_no_alpha var horizon_color: Color = Color(1.0, 0.55, 0.25)
@export_color_no_alpha var zenith_color: Color = Color(0.15, 0.25, 0.55)

var rd: RenderingDevice
var shader_rid: RID
var pipeline_rid: RID
var copy_shader_rid: RID
var copy_pipeline_rid: RID
var sampler_rid: RID

func _init() -> void:
	effect_callback_type = CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	_apply_preset()

func _apply_preset() -> void:
	match fog_preset:
		FogPreset.SUNSET_ATMOSPHERE:
			fog_density = 1.2
			fog_start = 2.0
			fog_end = 50.0
			height_falloff = 1.0
			horizon_color = Color(1.0, 0.55, 0.25)
			zenith_color = Color(0.15, 0.25, 0.55)
		FogPreset.CYBERPUNK_NEON_HAZE:
			fog_density = 1.6
			fog_start = 1.0
			fog_end = 40.0
			height_falloff = 1.5
			horizon_color = Color(1.0, 0.1, 0.7)
			zenith_color = Color(0.05, 0.1, 0.4)
		FogPreset.DEEP_OCEAN_MIST:
			fog_density = 1.0
			fog_start = 0.5
			fog_end = 30.0
			height_falloff = 0.8
			horizon_color = Color(0.1, 0.6, 0.7)
			zenith_color = Color(0.02, 0.1, 0.2)

func _ensure_shaders() -> bool:
	if rd == null:
		rd = RenderingServer.get_rendering_device()
	if rd == null:
		return false

	if not sampler_rid.is_valid():
		var sampler_state := RDSamplerState.new()
		sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
		sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
		sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
		sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
		sampler_rid = rd.sampler_create(sampler_state)

	if not shader_rid.is_valid():
		var shader_file = load("res://Compositor Effects/shaders/fog_gradient.glsl")
		if shader_file == null:
			return false
		var spirv: RDShaderSPIRV = shader_file.get_spirv()
		shader_rid = rd.shader_create_from_spirv(spirv)
		if not shader_rid.is_valid():
			return false
		pipeline_rid = rd.compute_pipeline_create(shader_rid)

	if not copy_shader_rid.is_valid():
		var copy_file = load("res://Compositor Effects/shaders/copy_image.glsl")
		if copy_file == null:
			return false
		var copy_spirv: RDShaderSPIRV = copy_file.get_spirv()
		copy_shader_rid = rd.shader_create_from_spirv(copy_spirv)
		if not copy_shader_rid.is_valid():
			return false
		copy_pipeline_rid = rd.compute_pipeline_create(copy_shader_rid)

	return pipeline_rid.is_valid() and copy_pipeline_rid.is_valid() and sampler_rid.is_valid()

func _render_callback(p_effect_callback_type: int, p_render_data: RenderData) -> void:
	if p_effect_callback_type != effect_callback_type:
		return

	var render_scene_buffers: RenderSceneBuffersRD = p_render_data.get_render_scene_buffers()
	if not render_scene_buffers:
		return

	if not _ensure_shaders():
		return

	var size: Vector2i = render_scene_buffers.get_internal_size()
	if size.x == 0 or size.y == 0:
		return

	var src_texture: RID = render_scene_buffers.get_color_layer(0)
	if not src_texture.is_valid():
		return

	var depth_texture: RID = render_scene_buffers.get_depth_layer(0)
	if not depth_texture.is_valid():
		return

	var tf := RDTextureFormat.new()
	tf.width = size.x
	tf.height = size.y
	tf.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	tf.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	var dest_texture: RID = rd.texture_create(tf, RDTextureView.new())

	var u_in1 := RDUniform.new()
	u_in1.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u_in1.binding = 0
	u_in1.add_id(sampler_rid)
	u_in1.add_id(src_texture)

	var u_out1 := RDUniform.new()
	u_out1.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_out1.binding = 1
	u_out1.add_id(dest_texture)

	var u_depth := RDUniform.new()
	u_depth.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u_depth.binding = 2
	u_depth.add_id(sampler_rid)
	u_depth.add_id(depth_texture)

	var uniform_set1: RID = rd.uniform_set_create([u_in1, u_out1, u_depth], shader_rid, 0)

	var p_array := PackedFloat32Array([
		fog_density,
		fog_start,
		fog_end,
		height_falloff,
		z_near,
		z_far,
		0.0,
		0.0,
		horizon_color.r,
		horizon_color.g,
		horizon_color.b,
		horizon_color.a,
		zenith_color.r,
		zenith_color.g,
		zenith_color.b,
		zenith_color.a
	])
	var push_constants: PackedByteArray = p_array.to_byte_array()

	var x_groups: int = (size.x + 7) / 8
	var y_groups: int = (size.y + 7) / 8

	var compute_list1: int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list1, pipeline_rid)
	rd.compute_list_bind_uniform_set(compute_list1, uniform_set1, 0)
	rd.compute_list_set_push_constant(compute_list1, push_constants, push_constants.size())
	rd.compute_list_dispatch(compute_list1, x_groups, y_groups, 1)
	rd.compute_list_end()

	var u_in2 := RDUniform.new()
	u_in2.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_in2.binding = 0
	u_in2.add_id(dest_texture)

	var u_out2 := RDUniform.new()
	u_out2.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_out2.binding = 1
	u_out2.add_id(src_texture)

	var uniform_set2: RID = rd.uniform_set_create([u_in2, u_out2], copy_shader_rid, 0)

	var compute_list2: int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list2, copy_pipeline_rid)
	rd.compute_list_bind_uniform_set(compute_list2, uniform_set2, 0)
	rd.compute_list_dispatch(compute_list2, x_groups, y_groups, 1)
	rd.compute_list_end()

	rd.free_rid(dest_texture)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if rd:
			if sampler_rid.is_valid():
				rd.free_rid(sampler_rid)
			if shader_rid.is_valid():
				rd.free_rid(shader_rid)
			if copy_shader_rid.is_valid():
				rd.free_rid(copy_shader_rid)
