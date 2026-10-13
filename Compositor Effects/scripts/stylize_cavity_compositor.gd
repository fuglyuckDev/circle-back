@tool
class_name StylizeCavityCompositorEffect
extends CompositorEffect

## Master blend amount (0 = off).
@export_range(0.0, 1.0, 0.05) var strength: float = 0.7
## Darkening of concave creases (Blender-style cavity).
@export_range(0.0, 2.0, 0.05) var cavity_strength: float = 0.8
## Brightening of convex ridges.
@export_range(0.0, 2.0, 0.05) var ridge_strength: float = 0.3
## Curvature response softness (higher = more sensitive / harder edges).
@export_range(0.0, 8.0, 0.1) var smooth: float = 3.0
## Depth difference (meters) at which cavity is gated off (silhouette guard).
@export_range(0.01, 5.0, 0.05) var depth_threshold: float = 1.0

var rd: RenderingDevice
var shader_rid: RID
var pipeline_rid: RID
var copy_shader_rid: RID
var copy_pipeline_rid: RID
var sampler_rid: RID

func _init() -> void:
	effect_callback_type = CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	access_resolved_depth = true
	needs_normal_roughness = true

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
	if not shader_rid.is_valid():
		var f = load("res://Compositor Effects/shaders/stylize_cavity.glsl")
		if f == null:
			return false
		var sp: RDShaderSPIRV = f.get_spirv()
		shader_rid = rd.shader_create_from_spirv(sp)
		if not shader_rid.is_valid():
			return false
		pipeline_rid = rd.compute_pipeline_create(shader_rid)
	if not copy_shader_rid.is_valid():
		var f = load("res://Compositor Effects/shaders/copy_image.glsl")
		if f == null:
			return false
		var sp: RDShaderSPIRV = f.get_spirv()
		copy_shader_rid = rd.shader_create_from_spirv(sp)
		if not copy_shader_rid.is_valid():
			return false
		copy_pipeline_rid = rd.compute_pipeline_create(copy_shader_rid)
	return pipeline_rid.is_valid() and copy_pipeline_rid.is_valid() and sampler_rid.is_valid()

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
	var src: RID = rsb.get_color_layer(0)
	var depth_tex: RID = rsb.get_depth_layer(0)
	if not src.is_valid() or not depth_tex.is_valid():
		return
	if not rsb.has_texture("forward_clustered", "normal_roughness"):
		return
	var normal_tex: RID = rsb.get_texture("forward_clustered", "normal_roughness")
	var z_near := 0.05
	var z_far := 100.0
	var sd: RenderSceneData = p_render_data.get_render_scene_data()
	if sd:
		var proj: Projection = sd.get_cam_projection()
		z_near = proj.get_z_near()
		z_far = proj.get_z_far()

	var tf := RDTextureFormat.new()
	tf.width = size.x
	tf.height = size.y
	tf.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	tf.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	var dest: RID = rd.texture_create(tf, RDTextureView.new())

	var u0 := RDUniform.new()
	u0.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u0.binding = 0
	u0.add_id(sampler_rid)
	u0.add_id(src)
	var u1 := RDUniform.new()
	u1.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u1.binding = 1
	u1.add_id(dest)
	var u2 := RDUniform.new()
	u2.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u2.binding = 2
	u2.add_id(sampler_rid)
	u2.add_id(depth_tex)
	var u3 := RDUniform.new()
	u3.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u3.binding = 3
	u3.add_id(sampler_rid)
	u3.add_id(normal_tex)
	var set0: RID = rd.uniform_set_create([u0, u1, u2, u3], shader_rid, 0)

	var pc := PackedFloat32Array([
		strength, cavity_strength, ridge_strength, smooth, depth_threshold, z_near, z_far,
		0, 0, 0, 0, 0, 0, 0, 0, 0
	]).to_byte_array()

	var xg := (size.x + 7) / 8
	var yg := (size.y + 7) / 8
	var cl: int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, pipeline_rid)
	rd.compute_list_bind_uniform_set(cl, set0, 0)
	rd.compute_list_set_push_constant(cl, pc, pc.size())
	rd.compute_list_dispatch(cl, xg, yg, 1)
	rd.compute_list_end()

	var ua := RDUniform.new()
	ua.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	ua.binding = 0
	ua.add_id(dest)
	var ub := RDUniform.new()
	ub.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	ub.binding = 1
	ub.add_id(src)
	var set1: RID = rd.uniform_set_create([ua, ub], copy_shader_rid, 0)
	var cl2: int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl2, copy_pipeline_rid)
	rd.compute_list_bind_uniform_set(cl2, set1, 0)
	rd.compute_list_dispatch(cl2, xg, yg, 1)
	rd.compute_list_end()

	rd.free_rid(dest)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if rd:
			if sampler_rid.is_valid():
				rd.free_rid(sampler_rid)
			if shader_rid.is_valid():
				rd.free_rid(shader_rid)
			if copy_shader_rid.is_valid():
				rd.free_rid(copy_shader_rid)