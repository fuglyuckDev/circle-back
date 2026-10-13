@tool
class_name BloomCompositorEffect
extends CompositorEffect

## Bloom threshold.
@export_range(0.0, 5.0, 0.1) var threshold: float = 1.0
## Threshold knee softness.
@export_range(0.0, 2.0, 0.1) var knee: float = 0.5
## Bloom intensity multiplier.
@export_range(0.0, 3.0, 0.05) var intensity: float = 0.8
## Filter radius dispersion.
@export_range(0.5, 2.0, 0.05) var filter_radius: float = 1.0
## Number of downsampling passes.
@export_range(1, 6, 1) var mip_levels: int = 5

var rd: RenderingDevice
var extract_shader_rid: RID
var extract_pipeline_rid: RID
var down_shader_rid: RID
var down_pipeline_rid: RID
var up_shader_rid: RID
var up_pipeline_rid: RID
var apply_shader_rid: RID
var apply_pipeline_rid: RID
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

	if not extract_shader_rid.is_valid():
		var sf = load("res://Compositor Effects/shaders/bloom_extract.glsl")
		if sf == null: return false
		extract_shader_rid = rd.shader_create_from_spirv(sf.get_spirv())
		if extract_shader_rid.is_valid(): extract_pipeline_rid = rd.compute_pipeline_create(extract_shader_rid)

	if not down_shader_rid.is_valid():
		var sf = load("res://Compositor Effects/shaders/bloom_down.glsl")
		if sf == null: return false
		down_shader_rid = rd.shader_create_from_spirv(sf.get_spirv())
		if down_shader_rid.is_valid(): down_pipeline_rid = rd.compute_pipeline_create(down_shader_rid)

	if not up_shader_rid.is_valid():
		var sf = load("res://Compositor Effects/shaders/bloom_up.glsl")
		if sf == null: return false
		up_shader_rid = rd.shader_create_from_spirv(sf.get_spirv())
		if up_shader_rid.is_valid(): up_pipeline_rid = rd.compute_pipeline_create(up_shader_rid)

	if not apply_shader_rid.is_valid():
		var sf = load("res://Compositor Effects/shaders/bloom_apply.glsl")
		if sf == null: return false
		apply_shader_rid = rd.shader_create_from_spirv(sf.get_spirv())
		if apply_shader_rid.is_valid(): apply_pipeline_rid = rd.compute_pipeline_create(apply_shader_rid)

	if not copy_shader_rid.is_valid():
		var copy_file = load("res://Compositor Effects/shaders/copy_image.glsl")
		if copy_file == null: return false
		copy_shader_rid = rd.shader_create_from_spirv(copy_file.get_spirv())
		if copy_shader_rid.is_valid(): copy_pipeline_rid = rd.compute_pipeline_create(copy_shader_rid)

	return extract_pipeline_rid.is_valid() and down_pipeline_rid.is_valid() and up_pipeline_rid.is_valid() and apply_pipeline_rid.is_valid() and copy_pipeline_rid.is_valid()

func _render_callback(p_effect_callback_type: int, p_render_data: RenderData) -> void:
	if p_effect_callback_type != effect_callback_type: return
	var render_scene_buffers: RenderSceneBuffersRD = p_render_data.get_render_scene_buffers()
	if not render_scene_buffers: return
	if not _ensure_shaders(): return

	var size: Vector2i = render_scene_buffers.get_internal_size()
	if size.x == 0 or size.y == 0: return
	var src_texture: RID = render_scene_buffers.get_color_layer(0)
	if not src_texture.is_valid(): return

	var num_mips: int = clampi(mip_levels, 1, 6)

	# Create mip chain textures (each half the size of the previous)
	var mip_textures: Array[RID] = []
	var mip_sizes: Array[Vector2i] = []
	var current_size := size

	for i in range(num_mips + 1):
		# Mip 0 is the extract output at full res, mip 1..N are downsampled
		if i > 0:
			current_size = Vector2i(maxi(current_size.x / 2, 1), maxi(current_size.y / 2, 1))

		var tf := RDTextureFormat.new()
		tf.width = current_size.x
		tf.height = current_size.y
		tf.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
		tf.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
		mip_textures.append(rd.texture_create(tf, RDTextureView.new()))
		mip_sizes.append(current_size)

	# ---- Pass 1: Brightness extract (src -> mip[0]) ----
	var u_ext_in := RDUniform.new()
	u_ext_in.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u_ext_in.binding = 0
	u_ext_in.add_id(sampler_rid)
	u_ext_in.add_id(src_texture)

	var u_ext_out := RDUniform.new()
	u_ext_out.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_ext_out.binding = 1
	u_ext_out.add_id(mip_textures[0])

	var us_ext: RID = rd.uniform_set_create([u_ext_in, u_ext_out], extract_shader_rid, 0)
	var pc_ext := PackedFloat32Array([threshold, knee, 0.0, 0.0]).to_byte_array()

	var cl: int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, extract_pipeline_rid)
	rd.compute_list_bind_uniform_set(cl, us_ext, 0)
	rd.compute_list_set_push_constant(cl, pc_ext, pc_ext.size())
	rd.compute_list_dispatch(cl, (mip_sizes[0].x + 7) / 8, (mip_sizes[0].y + 7) / 8, 1)
	rd.compute_list_end()

	# ---- Pass 2: Progressive downsample (mip[i] -> mip[i+1]) ----
	for i in range(num_mips):
		var src_mip: RID = mip_textures[i]
		var dst_mip: RID = mip_textures[i + 1]
		var src_sz: Vector2i = mip_sizes[i]
		var dst_sz: Vector2i = mip_sizes[i + 1]

		var u_down_in := RDUniform.new()
		u_down_in.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		u_down_in.binding = 0
		u_down_in.add_id(sampler_rid)
		u_down_in.add_id(src_mip)

		var u_down_out := RDUniform.new()
		u_down_out.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		u_down_out.binding = 1
		u_down_out.add_id(dst_mip)

		var us_down: RID = rd.uniform_set_create([u_down_in, u_down_out], down_shader_rid, 0)
		var inv_src := Vector2(1.0 / float(src_sz.x), 1.0 / float(src_sz.y))
		var pc_down := PackedFloat32Array([inv_src.x, inv_src.y, 0.0, 0.0]).to_byte_array()

		cl = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(cl, down_pipeline_rid)
		rd.compute_list_bind_uniform_set(cl, us_down, 0)
		rd.compute_list_set_push_constant(cl, pc_down, pc_down.size())
		rd.compute_list_dispatch(cl, (dst_sz.x + 7) / 8, (dst_sz.y + 7) / 8, 1)
		rd.compute_list_end()

	# ---- Pass 3: Progressive upsample + accumulate (mip[i+1] -> mip[i]) ----
	# Walk back up the chain, upsampling each mip and adding it to the one above
	for i in range(num_mips - 1, -1, -1):
		var src_mip: RID = mip_textures[i + 1]
		var dst_mip: RID = mip_textures[i]
		var src_sz: Vector2i = mip_sizes[i + 1]
		var dst_sz: Vector2i = mip_sizes[i]

		var u_up_in := RDUniform.new()
		u_up_in.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		u_up_in.binding = 0
		u_up_in.add_id(sampler_rid)
		u_up_in.add_id(src_mip)

		var u_up_out := RDUniform.new()
		u_up_out.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		u_up_out.binding = 1
		u_up_out.add_id(dst_mip)

		var us_up: RID = rd.uniform_set_create([u_up_in, u_up_out], up_shader_rid, 0)
		var inv_src := Vector2(1.0 / float(src_sz.x), 1.0 / float(src_sz.y))
		var pc_up := PackedFloat32Array([inv_src.x, inv_src.y, filter_radius, 0.0]).to_byte_array()

		cl = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(cl, up_pipeline_rid)
		rd.compute_list_bind_uniform_set(cl, us_up, 0)
		rd.compute_list_set_push_constant(cl, pc_up, pc_up.size())
		rd.compute_list_dispatch(cl, (dst_sz.x + 7) / 8, (dst_sz.y + 7) / 8, 1)
		rd.compute_list_end()

	# ---- Pass 4: Apply bloom (additive blend mip[0] onto scene) ----
	var u_app_in := RDUniform.new()
	u_app_in.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u_app_in.binding = 0
	u_app_in.add_id(sampler_rid)
	u_app_in.add_id(mip_textures[0])

	var u_app_out := RDUniform.new()
	u_app_out.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_app_out.binding = 1
	u_app_out.add_id(src_texture)

	var us_app: RID = rd.uniform_set_create([u_app_in, u_app_out], apply_shader_rid, 0)
	var pc_app := PackedFloat32Array([intensity, 0.0, 0.0, 0.0]).to_byte_array()

	cl = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, apply_pipeline_rid)
	rd.compute_list_bind_uniform_set(cl, us_app, 0)
	rd.compute_list_set_push_constant(cl, pc_app, pc_app.size())
	rd.compute_list_dispatch(cl, (size.x + 7) / 8, (size.y + 7) / 8, 1)
	rd.compute_list_end()

	# Free all mip textures
	for tex in mip_textures:
		rd.free_rid(tex)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if rd:
			if sampler_rid.is_valid(): rd.free_rid(sampler_rid)
			if extract_shader_rid.is_valid(): rd.free_rid(extract_shader_rid)
			if down_shader_rid.is_valid(): rd.free_rid(down_shader_rid)
			if up_shader_rid.is_valid(): rd.free_rid(up_shader_rid)
			if apply_shader_rid.is_valid(): rd.free_rid(apply_shader_rid)
			if copy_shader_rid.is_valid(): rd.free_rid(copy_shader_rid)
