@tool
class_name StylizeHalftoneCompositorEffect
extends CompositorEffect

enum ColorMode { CMYK_PRINT, RGB_SCREEN, MONOCHROME_INK }
enum DotShape { CIRCLE, DIAMOND, LINE }

## Halftone dot grid size in pixels.
@export_range(2.0, 32.0, 0.5) var dot_size: float = 8.0
## Master halftone blend strength.
@export_range(0.0, 1.0, 0.05) var strength: float = 1.0
@export var color_mode: ColorMode = ColorMode.CMYK_PRINT
## Global screen angle offset in degrees.
@export_range(-180.0, 180.0, 1.0) var angle_offset: float = 0.0
## Dot edge anti-aliasing softness width.
@export_range(0.001, 0.2, 0.005) var aa_width: float = 0.02
## Dot radius scale multiplier.
@export_range(0.1, 2.0, 0.05) var dot_scale: float = 1.0
## Dot tonal response gamma.
@export_range(0.1, 3.0, 0.05) var dot_gamma: float = 1.0
@export var dot_shape: DotShape = DotShape.CIRCLE
@export var paper_color: Color = Color.WHITE
@export var ink_color: Color = Color.BLACK
## Cyan screen angle.
@export_range(-180.0, 180.0, 1.0) var angle_c: float = 15.0
## Magenta screen angle.
@export_range(-180.0, 180.0, 1.0) var angle_m: float = 75.0
## Yellow screen angle.
@export_range(-180.0, 180.0, 1.0) var angle_y: float = 0.0
## Black screen angle.
@export_range(-180.0, 180.0, 1.0) var angle_k: float = 45.0
## Red screen angle.
@export_range(-180.0, 180.0, 1.0) var angle_r: float = 15.0
## Green screen angle.
@export_range(-180.0, 180.0, 1.0) var angle_g: float = 75.0
## Blue screen angle.
@export_range(-180.0, 180.0, 1.0) var angle_b: float = 0.0
## Monochrome screen angle.
@export_range(-180.0, 180.0, 1.0) var angle_bw: float = 45.0

var rd: RenderingDevice
var shader_rid: RID
var pipeline_rid: RID
var copy_shader_rid: RID
var copy_pipeline_rid: RID
var sampler_rid: RID

func _init() -> void:
	effect_callback_type = CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT

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
		var shader_file = load("res://Compositor Effects/shaders/stylize_halftone.glsl")
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
		dot_size,
		strength,
		float(color_mode),
		angle_offset,
		aa_width,
		dot_scale,
		dot_gamma,
		float(dot_shape),
		paper_color.r,
		paper_color.g,
		paper_color.b,
		ink_color.r,
		ink_color.g,
		ink_color.b,
		angle_c,
		angle_m,
		angle_y,
		angle_k,
		angle_r,
		angle_g,
		angle_b,
		angle_bw,
		0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0
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
