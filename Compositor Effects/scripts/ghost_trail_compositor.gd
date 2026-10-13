@tool
class_name GhostTrailCompositorEffect
extends CompositorEffect

## Master blend amount (0 = off).
@export_range(0.0, 1.0, 0.05) var strength: float = 0.5
## How much of the accumulated ghost shows in the final mix.
@export_range(0.0, 1.0, 0.05) var trail_mix: float = 0.8
## Exponential decay of the accumulation (lower = longer trails).
@export_range(0.0, 0.95, 0.01) var decay: float = 0.85
## Motion-rewind scale for the velocity offset.
@export_range(0.0, 2.0, 0.05) var velocity_scale: float = 0.4

var rd: RenderingDevice
var acc_shader_rid: RID
var acc_pipeline_rid: RID
var composite_shader_rid: RID
var composite_pipeline_rid: RID
var copy_shader_rid: RID
var copy_pipeline_rid: RID
var sampler_rid: RID
var prev_texture: RID
var prev_size := Vector2i.ZERO

func _init() -> void:
	effect_callback_type = CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	needs_motion_vectors = true

func _ensure_shaders() -> bool:
	if rd == null:
		rd = RenderingServer.get_rendering_device()
	if rd == null:
		return false
	if not sampler_rid.is_valid():
		var s := RDSamplerState.new()
		s.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
		s.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
		s.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
		s.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
		sampler_rid = rd.sampler_create(s)
	if not acc_shader_rid.is_valid():
		var f = load("res://Compositor Effects/shaders/ghost_acc.glsl")
		if f == null:
			return false
		var sp: RDShaderSPIRV = f.get_spirv()
		acc_shader_rid = rd.shader_create_from_spirv(sp)
		if not acc_shader_rid.is_valid():
			return false
		acc_pipeline_rid = rd.compute_pipeline_create(acc_shader_rid)
	if not composite_shader_rid.is_valid():
		var f = load("res://Compositor Effects/shaders/ghost_composite.glsl")
		if f == null:
			return false
		var sp: RDShaderSPIRV = f.get_spirv()
		composite_shader_rid = rd.shader_create_from_spirv(sp)
		if not composite_shader_rid.is_valid():
			return false
		composite_pipeline_rid = rd.compute_pipeline_create(composite_shader_rid)
	if not copy_shader_rid.is_valid():
		var f = load("res://Compositor Effects/shaders/copy_image.glsl")
		if f == null:
			return false
		var sp: RDShaderSPIRV = f.get_spirv()
		copy_shader_rid = rd.shader_create_from_spirv(sp)
		if not copy_shader_rid.is_valid():
			return false
		copy_pipeline_rid = rd.compute_pipeline_create(copy_shader_rid)
	return acc_pipeline_rid.is_valid() and composite_pipeline_rid.is_valid() and copy_pipeline_rid.is_valid() and sampler_rid.is_valid()

func _ensure_prev(size: Vector2i) -> bool:
	if prev_texture.is_valid() and prev_size == size:
		return true
	if prev_texture.is_valid():
		rd.free_rid(prev_texture)
		prev_texture = RID()
	var tf := RDTextureFormat.new()
	tf.width = size.x
	tf.height = size.y
	tf.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	tf.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	prev_texture = rd.texture_create(tf, RDTextureView.new())
	prev_size = size
	return prev_texture.is_valid()

func _render_callback(p_effect_callback_type: int, p_render_data: RenderData) -> void:
	if p_effect_callback_type != effect_callback_type:
		return
	var rsb: RenderSceneBuffersRD = p_render_data.get_render_scene_buffers()
	if not rsb:
		return
	if not _ensure_shaders():
		return
	var size: Vector2i = rsb.get_internal_size()
	if size.x == 0 or size.y == 0:
		return
	if not _ensure_prev(size):
		return
	var src: RID = rsb.get_color_layer(0)
	if not src.is_valid():
		return
	var velocity: RID = rsb.get_velocity_layer(0)
	var has_velocity: bool = velocity.is_valid()

	var time: float = Time.get_ticks_msec() / 1000.0
	var xg := (size.x + 7) / 8
	var yg := (size.y + 7) / 8

	var tf := RDTextureFormat.new()
	tf.width = size.x
	tf.height = size.y
	tf.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	tf.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	var scratch: RID = rd.texture_create(tf, RDTextureView.new())
	var dest: RID = rd.texture_create(tf, RDTextureView.new())

	# ---- Pass 1: accumulate ghost into scratch ------------------------------
	var u0 := RDUniform.new()
	u0.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u0.binding = 0
	u0.add_id(sampler_rid)
	u0.add_id(src)
	var u1 := RDUniform.new()
	u1.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u1.binding = 1
	u1.add_id(scratch)
	var u2 := RDUniform.new()
	u2.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u2.binding = 2
	u2.add_id(sampler_rid)
	u2.add_id(prev_texture)
	var u3 := RDUniform.new()
	u3.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u3.binding = 3
	u3.add_id(sampler_rid)
	u3.add_id(velocity if has_velocity else src)
	var set_acc: RID = rd.uniform_set_create([u0, u1, u2, u3], acc_shader_rid, 0)
	var pc_acc := PackedFloat32Array([
		decay, velocity_scale, time, 1.0 if has_velocity else 0.0,
		0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
	]).to_byte_array()

	var list1: int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list1, acc_pipeline_rid)
	rd.compute_list_bind_uniform_set(list1, set_acc, 0)
	rd.compute_list_set_push_constant(list1, pc_acc, pc_acc.size())
	rd.compute_list_dispatch(list1, xg, yg, 1)
	rd.compute_list_end()

	# ---- Pass 2: store scratch back into the persistent prev buffer --------
	var ua := RDUniform.new()
	ua.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	ua.binding = 0
	ua.add_id(scratch)
	var ub := RDUniform.new()
	ub.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	ub.binding = 1
	ub.add_id(prev_texture)
	var set_prev: RID = rd.uniform_set_create([ua, ub], copy_shader_rid, 0)
	var list2: int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list2, copy_pipeline_rid)
	rd.compute_list_bind_uniform_set(list2, set_prev, 0)
	rd.compute_list_dispatch(list2, xg, yg, 1)
	rd.compute_list_end()

	# ---- Pass 3: composite ghost with current colour -----------------------
	var ua2 := RDUniform.new()
	ua2.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	ua2.binding = 0
	ua2.add_id(sampler_rid)
	ua2.add_id(src)
	var ub2 := RDUniform.new()
	ub2.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	ub2.binding = 1
	ub2.add_id(sampler_rid)
	ub2.add_id(scratch)
	var uc2 := RDUniform.new()
	uc2.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uc2.binding = 2
	uc2.add_id(dest)
	var set_comp: RID = rd.uniform_set_create([ua2, ub2, uc2], composite_shader_rid, 0)
	var pc_comp := PackedFloat32Array([strength, trail_mix, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]).to_byte_array()

	var list3: int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list3, composite_pipeline_rid)
	rd.compute_list_bind_uniform_set(list3, set_comp, 0)
	rd.compute_list_set_push_constant(list3, pc_comp, pc_comp.size())
	rd.compute_list_dispatch(list3, xg, yg, 1)
	rd.compute_list_end()

	# ---- Pass 4: copy back into the scene colour buffer --------------------
	var ua3 := RDUniform.new()
	ua3.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	ua3.binding = 0
	ua3.add_id(dest)
	var ub3 := RDUniform.new()
	ub3.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	ub3.binding = 1
	ub3.add_id(src)
	var set_copy: RID = rd.uniform_set_create([ua3, ub3], copy_shader_rid, 0)
	var list4: int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list4, copy_pipeline_rid)
	rd.compute_list_bind_uniform_set(list4, set_copy, 0)
	rd.compute_list_dispatch(list4, xg, yg, 1)
	rd.compute_list_end()

	rd.free_rid(scratch)
	rd.free_rid(dest)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if rd:
			if prev_texture.is_valid():
				rd.free_rid(prev_texture)
			if sampler_rid.is_valid():
				rd.free_rid(sampler_rid)
			if acc_shader_rid.is_valid():
				rd.free_rid(acc_shader_rid)
			if composite_shader_rid.is_valid():
				rd.free_rid(composite_shader_rid)
			if copy_shader_rid.is_valid():
				rd.free_rid(copy_shader_rid)