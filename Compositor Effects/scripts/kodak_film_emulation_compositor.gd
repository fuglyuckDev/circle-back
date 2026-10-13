@tool
class_name KodakFilmEmulationCompositorEffect
extends CompositorEffect

enum FilmEmulationPreset {
	DEFAULT_NEUTRAL,
	KODAK_VISION3_500T,
	KODAK_VISION3_250D,
	EASTMAN_5247,
	FUJI_VELVIA_50,
	AGFA_COLOR_XP2,
	TECHNICOLOR_3_STRIP,
	KODACHROME_64,
	BW_TRI_X_400,
	CUSTOM
}

@export_enum("Default / Neutral (Off)", "Kodak Vision3 500T", "Kodak Vision3 250D", "Eastman 5247", "Fuji Velvia 50", "Agfa Color XP2", "Technicolor 3-Strip", "Kodachrome 64", "B&W Tri-X 400", "Custom") var film_preset: int = FilmEmulationPreset.DEFAULT_NEUTRAL:
	set(value):
		film_preset = value
		_apply_preset()

## Exposure EV offset stops.
@export_range(-3.0, 3.0, 0.1) var exposure_ev: float = 0.0

## Midtone gamma slope contrast curve.
@export_range(0.5, 2.5, 0.05) var gamma: float = 1.0

## Filmic S-curve shoulder highlight roll-off softness.
@export_range(0.0, 1.0, 0.05) var filmic_shoulder: float = 0.0

## Filmic overall color saturation level.
@export_range(0.0, 2.0, 0.05) var saturation: float = 1.0

## Shadow tint split-toning intensity.
@export_range(0.0, 2.0, 0.05) var shadow_tint_weight: float = 0.0

@export_color_no_alpha var shadow_tint: Color = Color(0.5, 0.5, 0.5)

## Highlight tint split-toning intensity.
@export_range(0.0, 2.0, 0.05) var highlight_tint_weight: float = 0.0

@export_color_no_alpha var highlight_tint: Color = Color(0.5, 0.5, 0.5)

## Shadow crusher level to trim black point.
@export_range(0.0, 1.0, 0.05) var shadow_crush: float = 0.0

## Highlight crusher level to compress bright ceiling.
@export_range(0.0, 1.0, 0.05) var highlight_crush: float = 0.0

@export_color_no_alpha var lift: Color = Color(0.5, 0.5, 0.5)

@export_color_no_alpha var gain: Color = Color(0.5, 0.5, 0.5)

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
	match film_preset:
		FilmEmulationPreset.DEFAULT_NEUTRAL:
			exposure_ev = 0.0
			gamma = 1.0
			filmic_shoulder = 0.0
			saturation = 1.0
			shadow_tint_weight = 0.0
			shadow_tint = Color(0.5, 0.5, 0.5)
			highlight_tint_weight = 0.0
			highlight_tint = Color(0.5, 0.5, 0.5)
			shadow_crush = 0.0
			highlight_crush = 0.0
			lift = Color(0.5, 0.5, 0.5)
			gain = Color(0.5, 0.5, 0.5)
		FilmEmulationPreset.KODAK_VISION3_500T:
			exposure_ev = 0.0
			gamma = 0.98
			filmic_shoulder = 0.65
			saturation = 0.95
			shadow_tint_weight = 0.35
			shadow_tint = Color(0.20, 0.35, 0.50)
			highlight_tint_weight = 0.40
			highlight_tint = Color(1.0, 0.90, 0.75)
			shadow_crush = 0.0
			highlight_crush = 0.0
			lift = Color(0.51, 0.50, 0.49)
			gain = Color(0.50, 0.50, 0.50)
		FilmEmulationPreset.KODAK_VISION3_250D:
			exposure_ev = 0.1
			gamma = 1.0
			filmic_shoulder = 0.70
			saturation = 0.98
			shadow_tint_weight = 0.25
			shadow_tint = Color(0.20, 0.30, 0.40)
			highlight_tint_weight = 0.30
			highlight_tint = Color(1.0, 0.94, 0.85)
			shadow_crush = 0.0
			highlight_crush = 0.0
			lift = Color(0.50, 0.50, 0.50)
			gain = Color(0.50, 0.50, 0.50)
		FilmEmulationPreset.EASTMAN_5247:
			exposure_ev = -0.1
			gamma = 1.05
			filmic_shoulder = 0.70
			saturation = 0.90
			shadow_tint_weight = 0.60
			shadow_tint = Color(0.10, 0.30, 0.40)
			highlight_tint_weight = 0.55
			highlight_tint = Color(1.0, 0.85, 0.65)
			shadow_crush = 0.03
			highlight_crush = 0.0
			lift = Color(0.49, 0.50, 0.51)
			gain = Color(0.51, 0.50, 0.49)
		FilmEmulationPreset.FUJI_VELVIA_50:
			exposure_ev = 0.2
			gamma = 1.25
			filmic_shoulder = 0.60
			saturation = 1.35
			shadow_tint_weight = 0.80
			shadow_tint = Color(0.05, 0.15, 0.30)
			highlight_tint_weight = 0.75
			highlight_tint = Color(1.0, 0.95, 0.75)
			shadow_crush = 0.08
			highlight_crush = 0.04
			lift = Color(0.47, 0.49, 0.53)
			gain = Color(0.53, 0.51, 0.47)
		FilmEmulationPreset.AGFA_COLOR_XP2:
			exposure_ev = 0.1
			gamma = 0.95
			filmic_shoulder = 0.80
			saturation = 0.85
			shadow_tint_weight = 0.50
			shadow_tint = Color(0.20, 0.18, 0.30)
			highlight_tint_weight = 0.50
			highlight_tint = Color(0.98, 0.90, 0.78)
			shadow_crush = 0.0
			highlight_crush = 0.0
			lift = Color(0.51, 0.50, 0.49)
			gain = Color(0.49, 0.50, 0.51)
		FilmEmulationPreset.TECHNICOLOR_3_STRIP:
			exposure_ev = 0.1
			gamma = 1.15
			filmic_shoulder = 0.65
			saturation = 1.40
			shadow_tint_weight = 0.85
			shadow_tint = Color(0.10, 0.35, 0.45)
			highlight_tint_weight = 0.85
			highlight_tint = Color(1.0, 0.75, 0.45)
			shadow_crush = 0.06
			highlight_crush = 0.02
			lift = Color(0.48, 0.50, 0.52)
			gain = Color(0.54, 0.49, 0.46)
		FilmEmulationPreset.KODACHROME_64:
			exposure_ev = 0.0
			gamma = 1.10
			filmic_shoulder = 0.70
			saturation = 1.15
			shadow_tint_weight = 0.70
			shadow_tint = Color(0.18, 0.14, 0.25)
			highlight_tint_weight = 0.70
			highlight_tint = Color(1.0, 0.90, 0.68)
			shadow_crush = 0.04
			highlight_crush = 0.01
			lift = Color(0.50, 0.49, 0.51)
			gain = Color(0.51, 0.50, 0.49)
		FilmEmulationPreset.BW_TRI_X_400:
			exposure_ev = 0.0
			gamma = 1.20
			filmic_shoulder = 0.65
			saturation = 0.0
			shadow_tint_weight = 0.0
			shadow_tint = Color(0.5, 0.5, 0.5)
			highlight_tint_weight = 0.0
			highlight_tint = Color(0.5, 0.5, 0.5)
			shadow_crush = 0.08
			highlight_crush = 0.02
			lift = Color(0.49, 0.49, 0.49)
			gain = Color(0.51, 0.51, 0.51)

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
		var shader_file = load("res://Compositor Effects/shaders/kodak_film_emulation.glsl")
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
		exposure_ev,
		gamma,
		filmic_shoulder,
		saturation,
		shadow_tint_weight,
		highlight_tint_weight,
		shadow_crush,
		highlight_crush,
		lift.r,
		lift.g,
		lift.b,
		lift.a,
		gain.r,
		gain.g,
		gain.b,
		gain.a,
		shadow_tint.r,
		shadow_tint.g,
		shadow_tint.b,
		shadow_tint.a,
		highlight_tint.r,
		highlight_tint.g,
		highlight_tint.b,
		highlight_tint.a
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
