@tool
class_name NightVisionCompositorEffect
extends CompositorEffect

enum VisionMode {
	P43_GREEN_PHOSPHOR,
	P45_WHITE_PHOSPHOR,
	THERMAL_FLIR_IRONBOW,
	THERMAL_FLIR_RAINBOW,
	CUSTOM
}

@export_enum("P43 Green Phosphor", "P45 White Phosphor", "Thermal FLIR Ironbow", "Thermal FLIR Rainbow", "Custom") var vision_mode: int = VisionMode.P43_GREEN_PHOSPHOR:
	set(value):
		vision_mode = value
		_apply_preset()

@export_range(0.5, 5.0, 0.1) var light_gain: float = 2.2
@export_range(0.0, 0.5, 0.02) var sensor_noise: float = 0.12
@export_range(0.0, 3.0, 0.1) var phosphor_bloom: float = 1.2
@export_range(0.0, 1.0, 0.05) var scanline_darkness: float = 0.35
@export_range(0.5, 2.0, 0.05) var auto_gating_threshold: float = 0.85
@export_range(0.0, 1.0, 0.05) var vignette_intensity: float = 0.45
## Speed multiplier for night vision sensor noise / pulse animation.
@export_range(0.0, 5.0, 0.1) var animation_speed: float = 1.0
## Intensity multiplier for night vision sensor noise animation.
@export_range(0.0, 3.0, 0.1) var animation_intensity: float = 1.0

var rd: RenderingDevice
var shader_rid: RID
var pipeline_rid: RID
var copy_shader_rid: RID
var copy_pipeline_rid: RID
var sampler_rid: RID
var time_accum: float = 0.0

func _init() -> void:
	effect_callback_type = CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	_apply_preset()

func _apply_preset() -> void:
	match vision_mode:
		VisionMode.P43_GREEN_PHOSPHOR:
			light_gain = 2.2
			sensor_noise = 0.12
			phosphor_bloom = 1.2
			scanline_darkness = 0.35
			auto_gating_threshold = 0.85
			vignette_intensity = 0.45
		VisionMode.P45_WHITE_PHOSPHOR:
			light_gain = 2.0
			sensor_noise = 0.08
			phosphor_bloom = 1.0
			scanline_darkness = 0.25
			auto_gating_threshold = 0.90
			vignette_intensity = 0.40
		VisionMode.THERMAL_FLIR_IRONBOW:
			light_gain = 1.5
			sensor_noise = 0.05
			phosphor_bloom = 0.5
			scanline_darkness = 0.15
			auto_gating_threshold = 1.2
			vignette_intensity = 0.30
		VisionMode.THERMAL_FLIR_RAINBOW:
			light_gain = 1.5
			sensor_noise = 0.05
			phosphor_bloom = 0.5
			scanline_darkness = 0.15
			auto_gating_threshold = 1.2
			vignette_intensity = 0.30

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
		var shader_file = load("res://Compositor Effects/shaders/night_vision.glsl")
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

	time_accum += 0.0166 * animation_speed

	var size: Vector2i = render_scene_buffers.get_internal_size()
	if size.x == 0 or size.y == 0:
		return

	var src_texture: RID = render_scene_buffers.get_color_layer(0)
	if not src_texture.is_valid():
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

	var uniform_set1: RID = rd.uniform_set_create([u_in1, u_out1], shader_rid, 0)

	var p_array := PackedFloat32Array([
		float(vision_mode),
		light_gain,
		sensor_noise,
		phosphor_bloom,
		scanline_darkness,
		auto_gating_threshold,
		vignette_intensity,
		time_accum,
		animation_intensity,
		0.0,
		0.0,
		0.0
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
