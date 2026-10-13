@tool
class_name BloomChromaticCompositorEffect
extends CompositorEffect

enum ChromaticPreset {
	SPECTRAL_PRISM_BLOOM,
	SUBTLE_LENS_DISPERSION,
	HEAVY_RAINBOW_BLOOM,
	CUSTOM
}

@export_enum("Spectral Prism Bloom", "Subtle Lens Dispersion", "Heavy Rainbow Bloom", "Custom") var chromatic_preset: int = ChromaticPreset.SPECTRAL_PRISM_BLOOM:
	set(value):
		chromatic_preset = value
		_apply_preset()

## Chromatic dispersion bloom intensity multiplier.
@export_range(0.0, 5.0, 0.1) var bloom_intensity: float = 1.4

## Luminance cutoff threshold for emissive highlight bloom.
@export_range(0.0, 3.0, 0.05) var bloom_threshold: float = 0.65

## Spatial blur spread distance for chromatic dispersion bloom.
@export_range(0.5, 30.0, 0.5) var dispersion_spread: float = 12.0

## Wavelength RGB spectral prism separation scale.
@export_range(0.1, 3.0, 0.1) var spectral_separation: float = 1.2

@export_color_no_alpha var tint_color: Color = Color(1.0, 0.96, 0.92)

var rd: RenderingDevice
var shader_rid: RID
var pipeline_rid: RID
var sampler_rid: RID

func _init() -> void:
	effect_callback_type = CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	_apply_preset()

func _apply_preset() -> void:
	match chromatic_preset:
		ChromaticPreset.SPECTRAL_PRISM_BLOOM:
			bloom_intensity = 1.4
			bloom_threshold = 0.65
			dispersion_spread = 12.0
			spectral_separation = 1.2
			tint_color = Color(1.0, 0.96, 0.92)
		ChromaticPreset.SUBTLE_LENS_DISPERSION:
			bloom_intensity = 0.9
			bloom_threshold = 0.75
			dispersion_spread = 8.0
			spectral_separation = 0.6
			tint_color = Color(0.98, 0.95, 0.90)
		ChromaticPreset.HEAVY_RAINBOW_BLOOM:
			bloom_intensity = 2.2
			bloom_threshold = 0.50
			dispersion_spread = 18.0
			spectral_separation = 2.2
			tint_color = Color(1.0, 0.90, 0.85)

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
		var shader_file = load("res://Compositor Effects/shaders/bloom_chromatic.glsl")
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
		bloom_intensity,
		bloom_threshold,
		dispersion_spread,
		spectral_separation,
		tint_color.r,
		tint_color.g,
		tint_color.b,
		tint_color.a
	])
	var push_bytes0: PackedByteArray = p_array0.to_byte_array()
	push_bytes0.append_array(PackedInt32Array([0, 0, 0, 0]).to_byte_array())

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
		bloom_intensity,
		bloom_threshold,
		dispersion_spread,
		spectral_separation,
		tint_color.r,
		tint_color.g,
		tint_color.b,
		tint_color.a
	])
	var push_bytes1: PackedByteArray = p_array1.to_byte_array()
	push_bytes1.append_array(PackedInt32Array([1, 0, 0, 0]).to_byte_array())

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
