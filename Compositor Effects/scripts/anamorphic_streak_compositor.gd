@tool
class_name AnamorphicStreakCompositorEffect
extends CompositorEffect

enum CameraPreset {
	PANAVISION_PANAFLEX,
	ARRIFLEX_BL3,
	JDC_ANAMORPHIC,
	KODAK_FILM_STOCKS,
	CUSTOM
}

@export_enum("Panavision Panaflex", "Arriflex BL3", "J-D-C Anamorphic", "Kodak Film Stocks", "Custom") var camera_preset: int = CameraPreset.PANAVISION_PANAFLEX:
	set(value):
		camera_preset = value
		_apply_preset()

## Luminance cutoff threshold for horizontal flare generation.
@export_range(0.0, 5.0, 0.05) var streak_threshold: float = 0.85

## Intensity multiplier for the anamorphic flare core.
@export_range(0.0, 10.0, 0.1) var streak_intensity: float = 2.5

## Horizontal streak length spanning across the screen.
@export_range(0.5, 50.0, 0.5) var streak_length: float = 18.0

## Optical squeeze ratio for anamorphic glass flare.
@export_range(1.0, 3.0, 0.05) var squeeze_factor: float = 2.0

@export_color_no_alpha var streak_color_core: Color = Color(0.12, 0.45, 1.0)

@export_color_no_alpha var streak_color_fringe: Color = Color(0.02, 0.15, 0.8)

## Chromatic dispersion fringe separation factor.
@export_range(0.0, 5.0, 0.1) var dispersion: float = 1.2

## Peripheral lens vignetting attenuation on flare tails.
@export_range(0.0, 1.0, 0.05) var lens_vignette: float = 0.3

## Peripheral optical astigmatism streak length scaling.
@export_range(0.0, 2.0, 0.1) var astigmatism: float = 0.5

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
	match camera_preset:
		CameraPreset.PANAVISION_PANAFLEX:
			streak_threshold = 0.85
			streak_intensity = 2.8
			streak_length = 22.0
			squeeze_factor = 2.0
			streak_color_core = Color(0.10, 0.40, 1.0)
			streak_color_fringe = Color(0.02, 0.12, 0.75)
			dispersion = 1.4
			lens_vignette = 0.25
			astigmatism = 0.6
		CameraPreset.ARRIFLEX_BL3:
			streak_threshold = 0.90
			streak_intensity = 2.2
			streak_length = 16.0
			squeeze_factor = 1.75
			streak_color_core = Color(0.20, 0.60, 1.0)
			streak_color_fringe = Color(0.05, 0.25, 0.85)
			dispersion = 0.9
			lens_vignette = 0.20
			astigmatism = 0.4
		CameraPreset.JDC_ANAMORPHIC:
			streak_threshold = 0.80
			streak_intensity = 3.5
			streak_length = 28.0
			squeeze_factor = 2.0
			streak_color_core = Color(0.05, 0.35, 1.0)
			streak_color_fringe = Color(0.01, 0.08, 0.65)
			dispersion = 1.8
			lens_vignette = 0.35
			astigmatism = 0.8
		CameraPreset.KODAK_FILM_STOCKS:
			streak_threshold = 0.88
			streak_intensity = 2.0
			streak_length = 14.0
			squeeze_factor = 1.5
			streak_color_core = Color(0.30, 0.55, 0.95)
			streak_color_fringe = Color(0.10, 0.30, 0.80)
			dispersion = 0.7
			lens_vignette = 0.15
			astigmatism = 0.3

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
		var shader_file = load("res://Compositor Effects/shaders/anamorphic_streak.glsl")
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
		streak_threshold,
		streak_intensity,
		streak_length,
		squeeze_factor,
		streak_color_core.r,
		streak_color_core.g,
		streak_color_core.b,
		streak_color_core.a,
		streak_color_fringe.r,
		streak_color_fringe.g,
		streak_color_fringe.b,
		streak_color_fringe.a,
		dispersion,
		lens_vignette,
		astigmatism,
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
