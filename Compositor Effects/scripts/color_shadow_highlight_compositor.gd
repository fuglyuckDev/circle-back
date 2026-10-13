@tool
class_name ColorShadowHighlightCompositorEffect
extends CompositorEffect

enum GradingPreset {
	NEUTRAL_IDENTITY,
	HOLLYWOOD_BLOCKBUSTER,
	TEAL_AND_ORANGE,
	CINEMATIC_DESATURATED,
	CUSTOM
}

@export_enum("Neutral Identity", "Hollywood Blockbuster", "Teal and Orange", "Cinematic Desaturated", "Custom") var grading_preset: int = GradingPreset.NEUTRAL_IDENTITY:
	set(value):
		grading_preset = value
		_apply_preset()

## Shadow black point floor level crusher.
@export_range(0.0, 1.0, 0.02) var shadow_black_floor: float = 0.0

## Midtone gamma slope response balance.
@export_range(0.5, 2.0, 0.05) var midtone_gamma_balance: float = 1.0

## Highlight white point ceiling level crusher.
@export_range(0.0, 1.0, 0.02) var highlight_white_ceiling: float = 0.0

## Smart vibrance color saturation boost.
@export_range(-1.0, 1.0, 0.05) var vibrance: float = 0.0

@export_color_no_alpha var shadow_color: Color = Color(0.5, 0.5, 0.5)

@export_color_no_alpha var midtone_color: Color = Color(0.5, 0.5, 0.5)

@export_color_no_alpha var highlight_color: Color = Color(0.5, 0.5, 0.5)

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
	match grading_preset:
		GradingPreset.NEUTRAL_IDENTITY:
			shadow_black_floor = 0.0
			midtone_gamma_balance = 1.0
			highlight_white_ceiling = 0.0
			vibrance = 0.0
			shadow_color = Color(0.5, 0.5, 0.5)
			midtone_color = Color(0.5, 0.5, 0.5)
			highlight_color = Color(0.5, 0.5, 0.5)
		GradingPreset.HOLLYWOOD_BLOCKBUSTER:
			shadow_black_floor = 0.05
			midtone_gamma_balance = 1.05
			highlight_white_ceiling = 0.02
			vibrance = 0.25
			shadow_color = Color(0.20, 0.35, 0.50)
			midtone_color = Color(0.50, 0.50, 0.50)
			highlight_color = Color(0.60, 0.52, 0.40)
		GradingPreset.TEAL_AND_ORANGE:
			shadow_black_floor = 0.08
			midtone_gamma_balance = 1.10
			highlight_white_ceiling = 0.04
			vibrance = 0.40
			shadow_color = Color(0.10, 0.40, 0.55)
			midtone_color = Color(0.52, 0.48, 0.45)
			highlight_color = Color(0.65, 0.48, 0.35)
		GradingPreset.CINEMATIC_DESATURATED:
			shadow_black_floor = 0.04
			midtone_gamma_balance = 0.95
			highlight_white_ceiling = 0.0
			vibrance = -0.30
			shadow_color = Color(0.35, 0.45, 0.50)
			midtone_color = Color(0.48, 0.48, 0.48)
			highlight_color = Color(0.55, 0.52, 0.48)

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
		var shader_file = load("res://Compositor Effects/shaders/color_shadow_highlight.glsl")
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
		shadow_black_floor,
		midtone_gamma_balance,
		highlight_white_ceiling,
		vibrance,
		shadow_color.r,
		shadow_color.g,
		shadow_color.b,
		shadow_color.a,
		midtone_color.r,
		midtone_color.g,
		midtone_color.b,
		midtone_color.a,
		highlight_color.r,
		highlight_color.g,
		highlight_color.b,
		highlight_color.a
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
