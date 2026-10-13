@tool
class_name FilmGrainCompositorEffect
extends CompositorEffect

enum FilmStockPreset {
	KODAK_VISION3_500T,
	KODAK_VISION3_250D,
	KODAK_VISION3_50D,
	PANAVISION_VINTAGE_STOCK,
	CUSTOM
}

@export_enum("Kodak Vision3 500T (5219)", "Kodak Vision3 250D (5207)", "Kodak Vision3 50D (5203)", "Panavision Vintage Stock", "Custom") var film_stock_preset: int = FilmStockPreset.KODAK_VISION3_500T:
	set(value):
		film_stock_preset = value
		_apply_preset()

## Overall intensity scale of the film grain.
@export_range(0.0, 3.0, 0.05) var grain_intensity: float = 1.0

## Primary grain crystal size in pixels (1080p reference).
@export_range(0.5, 8.0, 0.1) var grain_size: float = 1.6

## How much of the coarser clumping layer to mix in (0 = fine only, 1 = coarse).
@export_range(0.0, 1.0, 0.05) var coarse_mix: float = 0.6

## Luminance where grain is densest (0 = shadows, 1 = highlights).
@export_range(0.0, 1.0, 0.01) var peak: float = 0.42

## Tonal width of the grain curve (higher = grain over a wider luma range).
@export_range(0.01, 1.0, 0.01) var rolloff: float = 0.4

## 0 = pure monochrome grain, 1 = full RGB dye-layer variation.
@export_range(0.0, 1.0, 0.05) var grain_chroma: float = 0.25

var rd: RenderingDevice
var shader_rid: RID
var pipeline_rid: RID
var copy_shader_rid: RID
var copy_pipeline_rid: RID
var sampler_rid: RID
var frame_counter: float = 0.0

func _init() -> void:
	effect_callback_type = CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	_apply_preset()

func _apply_preset() -> void:
	match film_stock_preset:
		FilmStockPreset.KODAK_VISION3_500T:
			# Fast stock (ISO 500), visible grain, warm chroma variation
			grain_intensity = 1.2
			grain_size = 1.8
			coarse_mix = 0.6
			peak = 0.42
			rolloff = 0.4
			grain_chroma = 0.28
		FilmStockPreset.KODAK_VISION3_250D:
			# Daylight balanced, moderate grain, neutral chroma
			grain_intensity = 0.85
			grain_size = 1.4
			coarse_mix = 0.55
			peak = 0.4
			rolloff = 0.45
			grain_chroma = 0.18
		FilmStockPreset.KODAK_VISION3_50D:
			# Fine grain slow stock, minimal grain, near-monochrome
			grain_intensity = 0.45
			grain_size = 1.0
			coarse_mix = 0.5
			peak = 0.38
			rolloff = 0.5
			grain_chroma = 0.1
		FilmStockPreset.PANAVISION_VINTAGE_STOCK:
			# Coarse vintage stock, heavy grain, strong chroma dye clouds
			grain_intensity = 1.8
			grain_size = 2.8
			coarse_mix = 0.7
			peak = 0.4
			rolloff = 0.35
			grain_chroma = 0.4

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
		var shader_file = load("res://Compositor Effects/shaders/film_grain.glsl")
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

	frame_counter += 1.0
	var seed_val: float = fmod(frame_counter, 1000.0)

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
		grain_intensity,
		grain_size,
		coarse_mix,
		peak,
		rolloff,
		grain_chroma,
		seed_val,
		0.0,
		0.0,
		0.0,
		0.0,
		0.0,
		0.0,
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
