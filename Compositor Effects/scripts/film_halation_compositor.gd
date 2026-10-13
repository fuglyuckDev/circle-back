@tool
class_name FilmHalationCompositorEffect
extends CompositorEffect

enum FilmStockPreset {
	KODAK_VISION3_500T,
	KODAK_VISION3_250D,
	KODAK_VISION3_50D,
	VINTAGE_SILVER_HALIDE,
	CUSTOM
}

@export_enum("Kodak Vision3 500T (5219)", "Kodak Vision3 250D (5207)", "Kodak Vision3 50D (5203)", "Vintage Silver Halide", "Custom") var film_stock_preset: int = FilmStockPreset.KODAK_VISION3_500T:
	set(value):
		film_stock_preset = value
		_apply_preset()

## Luminance cutoff threshold for photochemical red halation reflection.
@export_range(0.0, 5.0, 0.01) var halation_threshold: float = 0.75

## Intensity multiplier for the red emulsion halation bleed.
@export_range(0.0, 10.0, 0.1) var halation_intensity: float = 3.0

## Spatial radius of the anti-halation backing red reflection.
@export_range(0.5, 20.0, 0.1) var halation_spread: float = 4.5

@export_color_no_alpha var halation_color: Color = Color(1.0, 0.22, 0.04)

## Intensity of wide film layer scatter bloom.
@export_range(0.0, 5.0, 0.1) var glow_intensity: float = 0.8

## Blur radius for soft diffusion glow.
@export_range(0.5, 30.0, 0.5) var glow_spread: float = 12.0

## Anamorphic horizontal glow stretch factor to stretch bloom to the sides.
@export_range(0.5, 5.0, 0.1) var glow_horizontal_stretch: float = 1.0

@export_color_no_alpha var glow_tint: Color = Color(1.0, 0.92, 0.82)

## Kodak S-curve shoulder roll-off softness on overexposed highlights.
@export_range(0.1, 2.0, 0.05) var film_shoulder_rolloff: float = 0.9

## Speed of dynamic animation/flicker effects.
@export_range(0.0, 5.0, 0.1) var animation_speed: float = 1.0

## Intensity of dynamic animation/flicker effects.
@export_range(0.0, 3.0, 0.1) var animation_intensity: float = 1.0

var rd: RenderingDevice
var shader_rid: RID
var pipeline_rid: RID
var sampler_rid: RID
var time_accum: float = 0.0

func _init() -> void:
	effect_callback_type = CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	_apply_preset()

func _apply_preset() -> void:
	match film_stock_preset:
		FilmStockPreset.KODAK_VISION3_500T:
			halation_threshold = 0.70
			halation_intensity = 3.5
			halation_spread = 5.5
			halation_color = Color(1.0, 0.20, 0.03)
			glow_intensity = 0.90
			glow_spread = 14.0
			glow_horizontal_stretch = 1.0
			glow_tint = Color(1.0, 0.90, 0.78)
			film_shoulder_rolloff = 0.85
		FilmStockPreset.KODAK_VISION3_250D:
			halation_threshold = 0.75
			halation_intensity = 2.8
			halation_spread = 4.2
			halation_color = Color(1.0, 0.25, 0.05)
			glow_intensity = 0.75
			glow_spread = 11.0
			glow_horizontal_stretch = 1.0
			glow_tint = Color(1.0, 0.95, 0.88)
			film_shoulder_rolloff = 0.95
		FilmStockPreset.KODAK_VISION3_50D:
			halation_threshold = 0.82
			halation_intensity = 2.2
			halation_spread = 3.0
			halation_color = Color(1.0, 0.28, 0.08)
			glow_intensity = 0.60
			glow_spread = 8.0
			glow_horizontal_stretch = 1.0
			glow_tint = Color(0.98, 0.96, 0.92)
			film_shoulder_rolloff = 1.10
		FilmStockPreset.VINTAGE_SILVER_HALIDE:
			halation_threshold = 0.65
			halation_intensity = 4.5
			halation_spread = 7.0
			halation_color = Color(1.0, 0.15, 0.02)
			glow_intensity = 1.20
			glow_spread = 18.0
			glow_horizontal_stretch = 1.4
			glow_tint = Color(1.0, 0.85, 0.65)
			film_shoulder_rolloff = 0.75

func _ensure_shaders() -> bool:
	if rd == null:
		rd = RenderingServer.get_rendering_device()
	if rd == null:
		return false

	if not sampler_rid.is_valid():
		var sampler_state := RDSamplerState.new()
		sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
		sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
		sampler_state.mip_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
		sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
		sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
		sampler_rid = rd.sampler_create(sampler_state)

	if not shader_rid.is_valid():
		var shader_file = load("res://Compositor Effects/shaders/film_halation.glsl")
		if shader_file == null:
			return false
		var spirv: RDShaderSPIRV = shader_file.get_spirv()
		shader_rid = rd.shader_create_from_spirv(spirv)
		if not shader_rid.is_valid():
			return false
		pipeline_rid = rd.compute_pipeline_create(shader_rid)

	return pipeline_rid.is_valid() and sampler_rid.is_valid()

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

	time_accum += 0.0166 * animation_speed

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

	var p_array0 := PackedFloat32Array([
		halation_threshold,
		halation_intensity,
		halation_spread,
		time_accum,
		halation_color.r,
		halation_color.g,
		halation_color.b,
		halation_color.a,
		glow_intensity,
		glow_spread,
		film_shoulder_rolloff,
		glow_horizontal_stretch,
		glow_tint.r,
		glow_tint.g,
		glow_tint.b,
		glow_tint.a,
		animation_intensity
	])
	var push_bytes0: PackedByteArray = p_array0.to_byte_array()
	push_bytes0.append_array(PackedInt32Array([0, 0, 0]).to_byte_array())

	var x_groups: int = (size.x + 7) / 8
	var y_groups: int = (size.y + 7) / 8

	var compute_list1: int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list1, pipeline_rid)
	rd.compute_list_bind_uniform_set(compute_list1, uniform_set1, 0)
	rd.compute_list_set_push_constant(compute_list1, push_bytes0, push_bytes0.size())
	rd.compute_list_dispatch(compute_list1, x_groups, y_groups, 1)
	rd.compute_list_end()

	var u_in2 := RDUniform.new()
	u_in2.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u_in2.binding = 0
	u_in2.add_id(sampler_rid)
	u_in2.add_id(dest_texture)

	var u_out2 := RDUniform.new()
	u_out2.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_out2.binding = 1
	u_out2.add_id(src_texture)

	var uniform_set2: RID = rd.uniform_set_create([u_in2, u_out2], shader_rid, 0)

	var p_array1 := PackedFloat32Array([
		halation_threshold,
		halation_intensity,
		halation_spread,
		time_accum,
		halation_color.r,
		halation_color.g,
		halation_color.b,
		halation_color.a,
		glow_intensity,
		glow_spread,
		film_shoulder_rolloff,
		glow_horizontal_stretch,
		glow_tint.r,
		glow_tint.g,
		glow_tint.b,
		glow_tint.a,
		animation_intensity
	])
	var push_bytes1: PackedByteArray = p_array1.to_byte_array()
	push_bytes1.append_array(PackedInt32Array([1, 0, 0]).to_byte_array())

	var compute_list2: int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list2, pipeline_rid)
	rd.compute_list_bind_uniform_set(compute_list2, uniform_set2, 0)
	rd.compute_list_set_push_constant(compute_list2, push_bytes1, push_bytes1.size())
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
