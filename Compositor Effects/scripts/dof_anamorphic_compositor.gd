@tool
class_name DofAnamorphicCompositorEffect
extends CompositorEffect

enum BokehPreset {
	PANAVISION_2X_OVAL_BOKEH,
	ARRIFLEX_1_5X_OVAL_BOKEH,
	SPHERICAL_CIRCULAR_BOKEH,
	CUSTOM
}

enum DebugMode {
	OFF,
	DEPTH,
	COC,
	BLUR_RADIUS,
	MASKS
}

enum ResolutionMode {
	FULL_RESOLUTION,
	HALF_RESOLUTION
}

@export_enum("Panavision 2.0x Oval Bokeh", "Arriflex 1.5x Oval Bokeh", "Spherical Circular Bokeh", "Custom") var bokeh_preset: int = BokehPreset.PANAVISION_2X_OVAL_BOKEH:
	set(value):
		bokeh_preset = value
		_apply_preset()

## Center in-focus field distance boundary (in camera space units/meters).
@export_range(0.1, 100.0, 0.5) var focus_distance: float = 5.0

## Thickness of the sharp in-focus camera focal plane (in meters).
@export_range(0.0, 10.0, 0.2) var in_focus_width: float = 2.0

## Foreground blur transition range (in meters).
@export_range(0.1, 20.0, 0.5) var near_range: float = 3.0

## Background blur transition range (in meters).
@export_range(0.1, 50.0, 0.5) var far_range: float = 10.0

## Anamorphic oval bokeh squeeze ratio (2.0 = Panavision 2:1 vertical oval).
@export_range(0.5, 3.0, 0.1) var bokeh_squeeze_ratio: float = 2.0

## Highlight iris brightness boost multiplier for out-of-focus bokeh disks.
@export_range(0.0, 5.0, 0.1) var bokeh_intensity: float = 2.0

## Maximum Circle of Confusion (CoC) bokeh disk radius.
@export_range(1.0, 30.0, 0.5) var bokeh_max_radius: float = 14.0

## Maximum Circle of Confusion (CoC) bokeh disk radius for the near (foreground) layer.
@export_range(1.0, 30.0, 0.5) var bokeh_max_radius_near: float = 10.0

## Luminance cutoff threshold for emissive highlight bokeh disks.
@export_range(0.0, 2.0, 0.05) var bokeh_threshold: float = 0.65

## Camera near clipping plane distance.
@export_range(0.01, 10.0, 0.05) var z_near: float = 0.1

## Camera far clipping plane distance.
@export_range(10.0, 1000.0, 10.0) var z_far: float = 100.0

## Bokeh disk sample count (higher values = smoother bokeh, lower = faster).
@export_range(16, 128, 16) var sample_count: int = 64

## Anamorphic cat's eye lens vignetting bokeh deformation at screen corners.
@export_range(0.0, 2.0, 0.1) var cats_eye_strength: float = 0.7

## RGB chromatic dispersion fringing on specular bokeh disks.
@export_range(0.0, 3.0, 0.1) var chromatic_dispersion: float = 0.5

## Anamorphic optical radial bokeh tilt / swirl intensity towards screen corners.
@export_range(0.0, 2.0, 0.1) var edge_swirl_strength: float = 0.6

## DOF falloff: 0 = tight transitions, 1 = wide gradual ramp between sharp and blurred.
@export_range(0.0, 1.0, 0.05) var falloff: float = 0.5

## Debug preview: visualize depth, CoC, blur radius or the near/far masks instead of the final image.
@export_enum("Off", "Depth", "CoC", "Blur Radius", "Masks") var debug_mode: int = DebugMode.OFF

# ---- Quality / performance settings --------------------------------------

## Master quality knob. Sets resolution, sample count and mask blur iterations.
## Individual settings below still override the preset after it is applied.
@export_enum("Performance", "Balanced", "High", "Ultra") var quality_preset: int = 2:
	set(value):
		quality_preset = value
		_apply_quality_preset()

## Resolution the expensive bokeh gather runs at. Half resolution is ~4x cheaper
## and is where production DOF (FidelityFX, Eevee) works.
@export_enum("Full Resolution", "Half Resolution") var resolution_mode: int = ResolutionMode.HALF_RESOLUTION

## Feather width of the near/far mask blur in pixels. Higher values give wide,
## gradual sharp->blurred transitions instead of a hard mask cutout line.
@export_range(0.0, 24.0, 0.5) var mask_blur_px: float = 12.0

## Mask blur iterations (each iteration = one horizontal + one vertical separable
## pass). Two iterations give a much smoother, rounder feather for large discs at
## a negligible cost (the masks run at the working resolution).
@export_range(1, 2, 1) var mask_blur_iterations: int = 2

## Composite the near (foreground) blur layer over the far (background) layer
## with separate masks (higher quality, slightly more expensive).
@export var layered_mode: bool = true

## Anamorphic field-curvature swirl around the viewport centre.
@export var enable_swirl: bool = true

## Anamorphic cat's eye pinch toward the viewport corners.
@export var enable_cats_eye: bool = true

## RGB chromatic dispersion on the bokeh highlights (extra texture reads).
@export var enable_chromatic: bool = true

## Specular highlight boost that drives visible bokeh disks.
@export var enable_highlight_boost: bool = true

## Karis sparkle suppression for bright single-pixel specs.
@export var enable_karis: bool = true

## Per-pixel disc rotation to decorrelate under-sampling blind spots (temporal
## shimmer fix). Disable for a very slight speedup.
@export var enable_disc_rotation: bool = true

## Physically-based CoC growth curve (d/(focus+d)) instead of a linear smoothstep
## ramp. Grows faster near the focal plane and asymptotically beyond, like a real lens.
@export var use_physical_coc: bool = false

## Per-sample radial jitter to decorrelate bokeh ring banding.
@export var use_jitter: bool = true

var rd: RenderingDevice
var shader_rid: RID
var pipeline_rid: RID
var masks_shader_rid: RID
var masks_pipeline_rid: RID
var mask_blur_shader_rid: RID
var mask_blur_pipeline_rid: RID
var composite_shader_rid: RID
var composite_pipeline_rid: RID
var copy_shader_rid: RID
var copy_pipeline_rid: RID
var sampler_rid: RID

func _init() -> void:
	effect_callback_type = CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	_apply_preset()

## Quality tiers: Performance = half-res gather + 32 samples + 1 mask blur pass;
## Balanced/High = half-res + 48/64 samples + double mask blur; Ultra = full-res
## gather + 96 samples + double mask blur (4x the gather cost of Performance).
func _apply_quality_preset() -> void:
	match quality_preset:
		0: # Performance
			resolution_mode = ResolutionMode.HALF_RESOLUTION
			sample_count = 32
			mask_blur_iterations = 1
		1: # Balanced
			resolution_mode = ResolutionMode.HALF_RESOLUTION
			sample_count = 48
			mask_blur_iterations = 2
		2: # High
			resolution_mode = ResolutionMode.HALF_RESOLUTION
			sample_count = 64
			mask_blur_iterations = 2
		3: # Ultra
			resolution_mode = ResolutionMode.FULL_RESOLUTION
			sample_count = 96
			mask_blur_iterations = 2

func _apply_preset() -> void:
	match bokeh_preset:
		BokehPreset.PANAVISION_2X_OVAL_BOKEH:
			focus_distance = 5.0
			in_focus_width = 2.0
			near_range = 3.0
			far_range = 10.0
			bokeh_squeeze_ratio = 2.0
			bokeh_intensity = 2.0
			bokeh_max_radius = 14.0
			bokeh_max_radius_near = 11.0
			bokeh_threshold = 0.65
			z_near = 0.1
			z_far = 100.0
			sample_count = 64
			cats_eye_strength = 0.8
			chromatic_dispersion = 0.6
			edge_swirl_strength = 0.7
		BokehPreset.ARRIFLEX_1_5X_OVAL_BOKEH:
			focus_distance = 6.0
			in_focus_width = 2.5
			near_range = 3.5
			far_range = 12.0
			bokeh_squeeze_ratio = 1.5
			bokeh_intensity = 1.6
			bokeh_max_radius = 10.0
			bokeh_max_radius_near = 8.0
			bokeh_threshold = 0.70
			z_near = 0.1
			z_far = 100.0
			sample_count = 64
			cats_eye_strength = 0.5
			chromatic_dispersion = 0.4
			edge_swirl_strength = 0.4
		BokehPreset.SPHERICAL_CIRCULAR_BOKEH:
			focus_distance = 4.0
			in_focus_width = 1.5
			near_range = 2.0
			far_range = 8.0
			bokeh_squeeze_ratio = 1.0
			bokeh_intensity = 1.2
			bokeh_max_radius = 8.0
			bokeh_max_radius_near = 6.0
			bokeh_threshold = 0.75
			z_near = 0.1
			z_far = 100.0
			sample_count = 48
			cats_eye_strength = 0.0
			chromatic_dispersion = 0.2
			edge_swirl_strength = 0.0

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

	if not masks_shader_rid.is_valid():
		var f = load("res://Compositor Effects/shaders/dof_anamorphic_masks.glsl")
		if f == null:
			return false
		var sp: RDShaderSPIRV = f.get_spirv()
		masks_shader_rid = rd.shader_create_from_spirv(sp)
		if not masks_shader_rid.is_valid():
			return false
		masks_pipeline_rid = rd.compute_pipeline_create(masks_shader_rid)

	if not mask_blur_shader_rid.is_valid():
		var f = load("res://Compositor Effects/shaders/dof_anamorphic_mask_blur.glsl")
		if f == null:
			return false
		var sp: RDShaderSPIRV = f.get_spirv()
		mask_blur_shader_rid = rd.shader_create_from_spirv(sp)
		if not mask_blur_shader_rid.is_valid():
			return false
		mask_blur_pipeline_rid = rd.compute_pipeline_create(mask_blur_shader_rid)

	if not shader_rid.is_valid():
		var shader_file = load("res://Compositor Effects/shaders/dof_anamorphic.glsl")
		if shader_file == null:
			return false
		var spirv: RDShaderSPIRV = shader_file.get_spirv()
		shader_rid = rd.shader_create_from_spirv(spirv)
		if not shader_rid.is_valid():
			return false
		pipeline_rid = rd.compute_pipeline_create(shader_rid)

	if not composite_shader_rid.is_valid():
		var composite_file = load("res://Compositor Effects/shaders/dof_anamorphic_composite.glsl")
		if composite_file == null:
			return false
		var composite_spirv: RDShaderSPIRV = composite_file.get_spirv()
		composite_shader_rid = rd.shader_create_from_spirv(composite_spirv)
		if not composite_shader_rid.is_valid():
			return false
		composite_pipeline_rid = rd.compute_pipeline_create(composite_shader_rid)

	if not copy_shader_rid.is_valid():
		var copy_file = load("res://Compositor Effects/shaders/copy_image.glsl")
		if copy_file == null:
			return false
		var copy_spirv: RDShaderSPIRV = copy_file.get_spirv()
		copy_shader_rid = rd.shader_create_from_spirv(copy_spirv)
		if not copy_shader_rid.is_valid():
			return false
		copy_pipeline_rid = rd.compute_pipeline_create(copy_shader_rid)

	return pipeline_rid.is_valid() and composite_pipeline_rid.is_valid() and copy_pipeline_rid.is_valid() and sampler_rid.is_valid()

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

	var depth_texture: RID = render_scene_buffers.get_depth_layer(0)
	if not depth_texture.is_valid():
		return

	# The expensive gather runs at the working resolution (full or half). The
	# depth/colour buffers are bound full-res and sampled bilinearly, so half-res
	# implicitly downsamples them (FidelityFX-style).
	var working: Vector2i = size
	if resolution_mode == ResolutionMode.HALF_RESOLUTION:
		working = Vector2i(maxi(1, (size.x + 1) / 2), maxi(1, (size.y + 1) / 2))

	var tf_scratch := RDTextureFormat.new()
	tf_scratch.width = working.x
	tf_scratch.height = working.y
	tf_scratch.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	tf_scratch.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	var scratch_texture: RID = rd.texture_create(tf_scratch, RDTextureView.new())

	# Mask textures (working resolution): r = far mask, g = near mask, b = radius.
	var mask_texture: RID = rd.texture_create(tf_scratch, RDTextureView.new())
	var mask_temp_texture: RID = rd.texture_create(tf_scratch, RDTextureView.new())
	var mask_temp2_texture: RID = rd.texture_create(tf_scratch, RDTextureView.new())
	var mask_blur_texture: RID = rd.texture_create(tf_scratch, RDTextureView.new())

	var tf_dest := RDTextureFormat.new()
	tf_dest.width = size.x
	tf_dest.height = size.y
	tf_dest.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	tf_dest.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	var dest_texture: RID = rd.texture_create(tf_dest, RDTextureView.new())

	# ---- Pass 0a: compute far/near masks + dilated radius --------------------
	var u_mdepth := RDUniform.new()
	u_mdepth.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u_mdepth.binding = 0
	u_mdepth.add_id(sampler_rid)
	u_mdepth.add_id(depth_texture)

	var u_mout := RDUniform.new()
	u_mout.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_mout.binding = 1
	u_mout.add_id(mask_texture)

	var set_masks: RID = rd.uniform_set_create([u_mdepth, u_mout], masks_shader_rid, 0)
	var pc_masks := PackedFloat32Array([
		focus_distance, in_focus_width, near_range, far_range,
		falloff, bokeh_max_radius, bokeh_max_radius_near, z_near,
		z_far, 1.0 if use_physical_coc else 0.0, 0, 0, 0, 0, 0, 0
	]).to_byte_array()

	# ---- Pass 0b: separable mask blur. Each iteration is H then V (ping-pong)
	# so the masks feather isotropically instead of leaving a cross-shaped kernel.
	# mask_blur_iterations = 2 runs H,V,H,V for a much rounder, smoother feather.
	var blur_px: float = lerp(mask_blur_px * 0.25, mask_blur_px, falloff)
	var pc_blur_h := PackedFloat32Array([blur_px, 1.0, 0.0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]).to_byte_array()
	var pc_blur_v := PackedFloat32Array([blur_px, 0.0, 1.0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]).to_byte_array()

	var make_blur_set := func(src: RID, dst: RID) -> RID:
		var u_src := RDUniform.new()
		u_src.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		u_src.binding = 0
		u_src.add_id(sampler_rid)
		u_src.add_id(src)
		var u_dst := RDUniform.new()
		u_dst.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		u_dst.binding = 1
		u_dst.add_id(dst)
		return rd.uniform_set_create([u_src, u_dst], mask_blur_shader_rid, 0)

	var set_blur_h1: RID = make_blur_set.call(mask_texture, mask_temp_texture)
	var set_blur_v1: RID = make_blur_set.call(mask_temp_texture, mask_temp2_texture)
	var set_blur_h2: RID = make_blur_set.call(mask_temp2_texture, mask_temp_texture)
	var set_blur_vf: RID = make_blur_set.call(mask_temp_texture, mask_blur_texture)

	# ---- Pass 1: bokeh gather (working resolution) -> RGBA (color + alpha mask)
	var u_in1 := RDUniform.new()
	u_in1.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u_in1.binding = 0
	u_in1.add_id(sampler_rid)
	u_in1.add_id(src_texture)

	var u_out1 := RDUniform.new()
	u_out1.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_out1.binding = 1
	u_out1.add_id(scratch_texture)

	var u_depth := RDUniform.new()
	u_depth.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u_depth.binding = 2
	u_depth.add_id(sampler_rid)
	u_depth.add_id(depth_texture)

	var u_mask := RDUniform.new()
	u_mask.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u_mask.binding = 3
	u_mask.add_id(sampler_rid)
	u_mask.add_id(mask_blur_texture)

	var uniform_set1: RID = rd.uniform_set_create([u_in1, u_out1, u_depth, u_mask], shader_rid, 0)

	var p_array := PackedFloat32Array([
		focus_distance,
		in_focus_width,
		near_range,
		far_range,
		bokeh_squeeze_ratio,
		bokeh_intensity,
		bokeh_max_radius,
		bokeh_threshold,
		z_near,
		z_far,
		float(sample_count),
		cats_eye_strength,
		chromatic_dispersion,
		edge_swirl_strength,
		float(debug_mode),
		falloff,
		bokeh_max_radius_near,
		1.0 if enable_swirl else 0.0,
		1.0 if enable_cats_eye else 0.0,
		1.0 if enable_chromatic else 0.0,
		1.0 if enable_highlight_boost else 0.0,
		1.0 if enable_karis else 0.0,
		1.0 if enable_disc_rotation else 0.0,
		1.0 if layered_mode else 0.0,
		1.0 if use_physical_coc else 0.0,
		1.0 if use_jitter else 0.0,
		0.0,
		0.0
	])
	var push_constants: PackedByteArray = p_array.to_byte_array()

	var work_groups_x: int = (working.x + 7) / 8
	var work_groups_y: int = (working.y + 7) / 8
	var full_groups_x: int = (size.x + 7) / 8
	var full_groups_y: int = (size.y + 7) / 8

	var compute_list0: int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list0, masks_pipeline_rid)
	rd.compute_list_bind_uniform_set(compute_list0, set_masks, 0)
	rd.compute_list_set_push_constant(compute_list0, pc_masks, pc_masks.size())
	rd.compute_list_dispatch(compute_list0, work_groups_x, work_groups_y, 1)
	rd.compute_list_end()

	# Pass 0b: separable mask blur. First iteration: H (mask -> tmp), V (tmp -> tmp2).
	var compute_list0b: int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list0b, mask_blur_pipeline_rid)
	rd.compute_list_bind_uniform_set(compute_list0b, set_blur_h1, 0)
	rd.compute_list_set_push_constant(compute_list0b, pc_blur_h, pc_blur_h.size())
	rd.compute_list_dispatch(compute_list0b, work_groups_x, work_groups_y, 1)
	rd.compute_list_end()

	var compute_list0c: int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list0c, mask_blur_pipeline_rid)
	rd.compute_list_bind_uniform_set(compute_list0c, set_blur_v1, 0)
	rd.compute_list_set_push_constant(compute_list0c, pc_blur_v, pc_blur_v.size())
	rd.compute_list_dispatch(compute_list0c, work_groups_x, work_groups_y, 1)
	rd.compute_list_end()

	if mask_blur_iterations >= 2:
		# Second iteration: H (tmp2 -> tmp), V (tmp -> final). Doubles the feather
		# width and rounds the kernel; the gather consumes mask_blur_texture.
		var compute_list0d: int = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(compute_list0d, mask_blur_pipeline_rid)
		rd.compute_list_bind_uniform_set(compute_list0d, set_blur_h2, 0)
		rd.compute_list_set_push_constant(compute_list0d, pc_blur_h, pc_blur_h.size())
		rd.compute_list_dispatch(compute_list0d, work_groups_x, work_groups_y, 1)
		rd.compute_list_end()

	var compute_list0e: int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list0e, mask_blur_pipeline_rid)
	rd.compute_list_bind_uniform_set(compute_list0e, set_blur_vf, 0)
	rd.compute_list_set_push_constant(compute_list0e, pc_blur_v, pc_blur_v.size())
	rd.compute_list_dispatch(compute_list0e, work_groups_x, work_groups_y, 1)
	rd.compute_list_end()

	var compute_list1: int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list1, pipeline_rid)
	rd.compute_list_bind_uniform_set(compute_list1, uniform_set1, 0)
	rd.compute_list_set_push_constant(compute_list1, push_constants, push_constants.size())
	rd.compute_list_dispatch(compute_list1, work_groups_x, work_groups_y, 1)
	rd.compute_list_end()

	# ---- Pass 2: composite (full resolution) - blends base with blurred by mask
	var u_base := RDUniform.new()
	u_base.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u_base.binding = 0
	u_base.add_id(sampler_rid)
	u_base.add_id(src_texture)

	var u_blur := RDUniform.new()
	u_blur.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u_blur.binding = 1
	u_blur.add_id(sampler_rid)
	u_blur.add_id(scratch_texture)

	var u_out2 := RDUniform.new()
	u_out2.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_out2.binding = 2
	u_out2.add_id(dest_texture)

	var u_cdepth := RDUniform.new()
	u_cdepth.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u_cdepth.binding = 3
	u_cdepth.add_id(sampler_rid)
	u_cdepth.add_id(depth_texture)

	var uniform_set2: RID = rd.uniform_set_create([u_base, u_blur, u_out2, u_cdepth], composite_shader_rid, 0)
	var pc_composite := PackedFloat32Array([
		focus_distance, in_focus_width, near_range, far_range,
		z_near, z_far, 1.0 if use_physical_coc else 0.0,
		0, 0, 0, 0, 0, 0, 0, 0, 0
	]).to_byte_array()

	var compute_list2: int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list2, composite_pipeline_rid)
	rd.compute_list_bind_uniform_set(compute_list2, uniform_set2, 0)
	rd.compute_list_set_push_constant(compute_list2, pc_composite, pc_composite.size())
	rd.compute_list_dispatch(compute_list2, full_groups_x, full_groups_y, 1)
	rd.compute_list_end()

	# ---- Pass 3: copy back into the scene colour buffer --------------------
	var u_in3 := RDUniform.new()
	u_in3.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_in3.binding = 0
	u_in3.add_id(dest_texture)

	var u_out3 := RDUniform.new()
	u_out3.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_out3.binding = 1
	u_out3.add_id(src_texture)

	var uniform_set3: RID = rd.uniform_set_create([u_in3, u_out3], copy_shader_rid, 0)

	var compute_list3: int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list3, copy_pipeline_rid)
	rd.compute_list_bind_uniform_set(compute_list3, uniform_set3, 0)
	rd.compute_list_dispatch(compute_list3, full_groups_x, full_groups_y, 1)
	rd.compute_list_end()

	rd.free_rid(mask_texture)
	rd.free_rid(mask_temp_texture)
	rd.free_rid(mask_temp2_texture)
	rd.free_rid(mask_blur_texture)
	rd.free_rid(scratch_texture)
	rd.free_rid(dest_texture)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if rd:
			if sampler_rid.is_valid():
				rd.free_rid(sampler_rid)
			if masks_shader_rid.is_valid():
				rd.free_rid(masks_shader_rid)
			if mask_blur_shader_rid.is_valid():
				rd.free_rid(mask_blur_shader_rid)
			if shader_rid.is_valid():
				rd.free_rid(shader_rid)
			if composite_shader_rid.is_valid():
				rd.free_rid(composite_shader_rid)
			if copy_shader_rid.is_valid():
				rd.free_rid(copy_shader_rid)
