@tool
class_name DofRadialBokehCompositorEffect
extends CompositorEffect

enum RadialBokehPreset {
	PANAVISION_OVAL_RADIAL,
	ANAMORPHIC_VIGNETTE_BOKEH,
	SUPER8_SWIRL_BOKEH,
	CUSTOM
}

@export_enum("Panavision Oval Radial", "Anamorphic Vignette Bokeh", "Super-8 Swirl Bokeh", "Custom") var blur_preset: int = RadialBokehPreset.PANAVISION_OVAL_RADIAL:
	set(value):
		blur_preset = value
		_apply_preset()

## Sharp center field radius threshold before radial blur begins.
@export_range(0.0, 0.5, 0.02) var inner_radius: float = 0.15

## Radial distance blur transition falloff range.
@export_range(0.05, 1.0, 0.05) var blur_falloff: float = 0.40

## Anamorphic oval bokeh squeeze ratio (2.0 = Panavision 2:1 vertical oval).
@export_range(0.5, 3.0, 0.1) var bokeh_squeeze_ratio: float = 2.0

## Highlight iris brightness boost multiplier for peripheral bokeh disks.
@export_range(0.0, 5.0, 0.1) var bokeh_intensity: float = 2.0

## Maximum bokeh disk radius at screen corners.
@export_range(1.0, 30.0, 0.5) var bokeh_max_radius: float = 14.0

## Luminance cutoff threshold for emissive highlight bokeh disks.
@export_range(0.0, 2.0, 0.05) var bokeh_threshold: float = 0.65

## Anamorphic cat's eye lens vignetting bokeh deformation at screen corners.
@export_range(0.0, 2.0, 0.1) var cats_eye_strength: float = 0.7

## Anamorphic optical radial bokeh tilt / swirl intensity towards screen corners.
@export_range(0.0, 2.0, 0.1) var edge_swirl_strength: float = 0.6

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
	match blur_preset:
		RadialBokehPreset.PANAVISION_OVAL_RADIAL:
			inner_radius = 0.15
			blur_falloff = 0.40
			bokeh_squeeze_ratio = 2.0
			bokeh_intensity = 2.0
			bokeh_max_radius = 14.0
			bokeh_threshold = 0.65
			cats_eye_strength = 0.7
			edge_swirl_strength = 0.6
		RadialBokehPreset.ANAMORPHIC_VIGNETTE_BOKEH:
			inner_radius = 0.25
			blur_falloff = 0.35
			bokeh_squeeze_ratio = 1.6
			bokeh_intensity = 1.5
			bokeh_max_radius = 10.0
			bokeh_threshold = 0.70
			cats_eye_strength = 0.5
			edge_swirl_strength = 0.4
		RadialBokehPreset.SUPER8_SWIRL_BOKEH:
			inner_radius = 0.10
			blur_falloff = 0.50
			bokeh_squeeze_ratio = 2.5
			bokeh_intensity = 2.5
			bokeh_max_radius = 18.0
			bokeh_threshold = 0.60
			cats_eye_strength = 1.2
			edge_swirl_strength = 1.0

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
		var shader_file = load("res://Compositor Effects/shaders/dof_radial_bokeh.glsl")
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
		inner_radius,
		blur_falloff,
		bokeh_squeeze_ratio,
		bokeh_intensity,
		bokeh_max_radius,
		bokeh_threshold,
		cats_eye_strength,
		edge_swirl_strength
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
