#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;
layout(set = 0, binding = 2) uniform sampler2D depth_texture;
layout(set = 0, binding = 3) uniform sampler2D mask_texture;

layout(push_constant, std430) uniform Params {
	float focus_distance;
	float in_focus_width;
	float near_range;
	float far_range;
	float bokeh_squeeze_ratio;
	float bokeh_intensity;
	float bokeh_max_radius_far;
	float bokeh_threshold;
	float z_near;
	float z_far;
	float sample_count;
	float cats_eye_strength;
	float chromatic_dispersion;
	float edge_swirl_strength;
	float debug_mode;
	float falloff;
	float bokeh_max_radius_near;
	float enable_swirl;
	float enable_cats_eye;
	float enable_chromatic;
	float enable_highlight;
	float enable_karis;
	float enable_rotation;
	float layered_mode;
	float use_physical;
	float use_jitter;
	float pad0;
	float pad1;
} params;

float luma(vec3 color) {
	return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

float bright_pass(vec3 color, float mask_threshold, float mask_knee) {
	return smoothstep(mask_threshold, mask_threshold + mask_knee, luma(color));
}

float hash1(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float get_linear_depth(vec2 uv) {
	float raw_depth = texture(depth_texture, uv).r;
	float near_p = max(params.z_near, 0.01);
	float far_p = max(params.z_far, near_p + 1.0);
	// Godot 4 Reverse-Z depth linearization (raw_depth = 1.0 at near_p, 0.0 at far_p)
	return (near_p * far_p) / max(near_p + raw_depth * (far_p - near_p), 0.0001);
}

// Far/background CoC growth. Physically-based uses d/(focus+d), which grows
// asymptotically and faster near focus than the linear smoothstep ramp.
float far_coc(float depth, float far_plane) {
	if (params.use_physical > 0.5) {
		float d = max(depth - far_plane, 0.0);
		float denom = max(params.focus_distance + d, 0.0001);
		float norm = max(params.far_range / max(params.focus_distance + params.far_range, 0.0001), 0.0001);
		return clamp((d / denom) / norm, 0.0, 1.0);
	}
	return smoothstep(0.0, max(params.far_range, 0.05), depth - far_plane);
}

float near_coc(float depth, float near_plane) {
	if (params.use_physical > 0.5) {
		float d = max(near_plane - depth, 0.0);
		float denom = max(params.focus_distance + d, 0.0001);
		float norm = max(params.near_range / max(params.focus_distance + params.near_range, 0.0001), 0.0001);
		return clamp((d / denom) / norm, 0.0, 1.0);
	}
	return smoothstep(0.0, max(params.near_range, 0.05), near_plane - depth);
}

// Signed Circle of Confusion (CoC > 0 = far/background, CoC < 0 = near/foreground).
float compute_coc(float depth) {
	float half_focus = max(params.in_focus_width * 0.5, 0.01);
	float near_plane = params.focus_distance - half_focus;
	float far_plane = params.focus_distance + half_focus;

	if (depth > far_plane) {
		return far_coc(depth, far_plane);
	} else if (depth < near_plane) {
		return -near_coc(depth, near_plane);
	}
	return 0.0;
}

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(output_image);
	if (pos.x >= size.x || pos.y >= size.y) {
		return;
	}

	vec2 size_f = vec2(size);
	vec2 uv = (vec2(pos) + vec2(0.5)) / size_f;
	vec2 texel = (vec2(1.0) / size_f) * (float(size.y) / 1080.0);
	vec3 base_color = texture(input_texture, uv).rgb;

	float current_depth = get_linear_depth(uv);
	float center_coc = compute_coc(current_depth);
	float abs_center_coc = abs(center_coc);
	float center_radius = center_coc >= 0.0 ? params.bokeh_max_radius_far : params.bokeh_max_radius_near;
	float max_radius = max(params.bokeh_max_radius_far, params.bokeh_max_radius_near);

	// ---- Debug: depth ---------------------------------------------------
	if (params.debug_mode > 0.5 && params.debug_mode < 1.5) {
		float nd = clamp((current_depth - params.z_near) / max(params.z_far - params.z_near, 0.0001), 0.0, 1.0);
		vec3 dcol = vec3(1.0 - nd);
		float focus_dist = abs(current_depth - params.focus_distance);
		float focus_marker = 1.0 - smoothstep(params.in_focus_width * 0.5, params.in_focus_width * 0.5 + 1.0, focus_dist);
		dcol = mix(dcol, vec3(0.0, 1.0, 0.2), focus_marker * 0.8);
		imageStore(output_image, pos, vec4(dcol, 1.0));
		return;
	}

	// ---- Masks & dilated radius (computed + blurred by the mask passes) --
	// r = far mask, g = near mask (both already feathered in screen space),
	// b = 3x3 dilated CoC used for the gathering radius. The mask-blur pass
	// guarantees the dilation's outer edge is never a hard cut.
	vec3 m = texture(mask_texture, uv).rgb;
	float far_mask = m.r;
	float near_mask = m.g;
	float radius_coc = m.b;

	float center_size = abs_center_coc * center_radius;
	float max_blur = radius_coc * max_radius;

	// ---- Debug: signed CoC (smoothed, near vs far) ------------------------
	// The raw CoC is a per-pixel radius that is sharp at depth discontinuities.
	// What actually drives the blur is the screen-space smoothed mask (falloff),
	// so this preview shows that smoothed value, not the raw scalar.
	if (params.debug_mode > 1.5 && params.debug_mode < 2.5) {
		float t = clamp(max(far_mask, near_mask), 0.0, 1.0);
		vec3 ccol;
		if (center_coc < -0.01) {
			ccol = mix(vec3(0.05, 0.1, 0.6), vec3(0.1, 0.9, 0.9), t);      // foreground: blue -> cyan
		} else if (center_coc > 0.01) {
			ccol = mix(vec3(0.25, 0.1, 0.4), vec3(1.0, 0.8, 0.15), t);      // background: purple -> yellow
		} else {
			ccol = vec3(0.0, 0.0, 0.0);                                      // in focus
		}
		imageStore(output_image, pos, vec4(ccol, 1.0));
		return;
	}
	if (params.debug_mode > 2.5 && params.debug_mode < 3.5) {
		float rn = clamp(max_blur / max(max_radius, 0.001), 0.0, 1.0);
		imageStore(output_image, pos, vec4(vec3(rn), 1.0));
		return;
	}
	if (params.debug_mode > 3.5 && params.debug_mode < 4.5) {
		imageStore(output_image, pos, vec4(vec3(near_mask, far_mask, 0.0), 1.0)); // near=red, far=green
		return;
	}

	if (max_blur < 0.5) {
		imageStore(output_image, pos, vec4(base_color, 0.0)); // alpha 0 -> composite keeps base
		return;
	}

	// ---- Anamorphic field (OtisFX-style) --------------------------------
	// Aspect-correct, viewport-centred radial coordinates so the oval stretch
	// and the swirl revolve around the exact centre of the viewport.
	vec2 dpx = uv * size_f - size_f * 0.5;
	float rpx = length(dpx);
	vec2 radial_dir = rpx > 1e-4 ? dpx / rpx : vec2(1.0, 0.0);
	float rn = clamp(rpx / (0.5 * min(size.x, size.y)), 0.0, 1.0);

	float cos_t = 1.0;
	float sin_t = 0.0;
	if (params.enable_swirl > 0.5) {
		float swirl_tilt = rn * params.edge_swirl_strength * 2.0;
		cos_t = cos(swirl_tilt);
		sin_t = sin(swirl_tilt);
	}

	float edge_vignette = params.enable_cats_eye > 0.5 ? rn * rn * params.cats_eye_strength * 4.0 : 0.0;
	float squeeze = max(params.bokeh_squeeze_ratio + edge_vignette, 0.3);
	// Oval orientation: with the field-curvature swirl enabled the ovals lie
	// horizontally (classic anamorphic) and rotate toward the frame edges; with
	// the swirl disabled the ovals stand vertically instead.
	float stretch_x = params.enable_swirl > 0.5 ? squeeze : 1.0;
	float stretch_y = params.enable_swirl > 0.5 ? 1.0 : squeeze;

	// ---- Scatter-as-gather bokeh (Voxagon) with near/far layers ---------
	// Equal weight per contributing sample + running-average blending for
	// correct intensity and continuous discs. Background samples are clamped to
	// the centre's CoC so sharp content never gets a halo. Samples are split
	// into far and near buckets so we can composite near-over-far (layered).
	vec3 far_color = base_color;
	vec3 near_color = base_color;
	float far_tot = 1.0;
	float near_tot = 1.0;
	float golden_angle = 2.39996323;
	float rot = params.enable_rotation > 0.5 ? hash1(vec2(pos)) * 6.28318530718 : 0.0;
	int max_samples = int(clamp(params.sample_count * clamp(max_blur / 8.0, 1.0, 2.0), 16.0, 128.0));

	for (int i = 1; i <= 128; i++) {
		if (i > max_samples) break;

		float fi = float(i);
		// Radial jitter decorrelates the concentric-ring banding that the golden
		// spiral produces when under-sampled (Godot-style anti-banding).
		float jitter = params.use_jitter > 0.5 ? (hash1(vec2(pos) * 0.031 + float(i) * 13.37) - 0.5) * 0.4 : 0.0;
		float r = sqrt(fi / float(max_samples)) * max_blur * (1.0 + jitter); // circular offset in px
		float angle = fi * golden_angle + rot;

		vec2 circular = vec2(cos(angle), sin(angle)) * r;
		vec2 stretched = vec2(circular.x * stretch_x, circular.y * stretch_y);
		vec2 morphed = vec2(
			stretched.x * cos_t - stretched.y * sin_t,
			stretched.x * sin_t + stretched.y * cos_t
		);

		vec2 sample_uv = clamp(uv + morphed * texel, vec2(0.0), vec2(1.0));

		vec3 s_col;
		if (params.enable_chromatic > 0.5 && params.chromatic_dispersion > 0.001) {
			vec2 disp_off = radial_dir * params.chromatic_dispersion * r * texel * 0.4;
			vec2 uv_r = clamp(uv + morphed * texel + disp_off, vec2(0.0), vec2(1.0));
			vec2 uv_b = clamp(uv + morphed * texel - disp_off, vec2(0.0), vec2(1.0));
			s_col = vec3(
				texture(input_texture, uv_r).r,
				texture(input_texture, sample_uv).g,
				texture(input_texture, uv_b).b
			);
		} else {
			s_col = texture(input_texture, sample_uv).rgb;
		}

		// Highlight boost for specular bokeh disks (anamorphic bokeh is driven
		// by bright highlights).
		if (params.enable_highlight > 0.5) {
			float hl = bright_pass(s_col, params.bokeh_threshold, 0.4);
			s_col *= 1.0 + hl * params.bokeh_intensity * 3.0;
		}

		float sample_depth = get_linear_depth(sample_uv);
		float sample_coc = compute_coc(sample_depth);
		float sample_size = abs(sample_coc) * (sample_coc >= 0.0 ? params.bokeh_max_radius_far : params.bokeh_max_radius_near);

		// Background samples may only blur as much as the centre pixel's own
		// CoC (scaled 2x so blurred foreground still smears over background).
		if (sample_depth > current_depth) {
			sample_size = clamp(sample_size, 0.0, center_size * 2.0);
		}

		// Acceptance: the sample contributes when its own disc reaches this
		// pixel, ramped over one pixel, with a soft falloff at the disc edge.
		float m = smoothstep(r - 0.5, r + 0.5, sample_size);
		m *= 1.0 - smoothstep(max_blur * 0.8, max_blur, r);

		// Karis fold: bright single-pixel specs contribute less (no sparkle).
		if (params.enable_karis > 0.5) {
			m *= 0.5 + 0.5 * (1.0 / (1.0 + luma(s_col)));
		}

		if (sample_coc >= 0.0) {
			far_color += mix(far_color / far_tot, s_col, m);
			far_tot += 1.0;
		} else {
			near_color += mix(near_color / near_tot, s_col, m);
			near_tot += 1.0;
		}
	}

	vec3 far_blur = far_color / max(far_tot, 0.0001);
	vec3 near_blur = near_color / max(near_tot, 0.0001);

	// cocToAlpha-style masks (Filament): no blend below the in-focus CoC,
	// then a progressive ramp.
	float far_alpha = smoothstep(0.02, 0.4, far_mask);
	float near_alpha = smoothstep(0.02, 0.4, near_mask);

	vec3 out_rgb;
	float out_a;
	if (params.layered_mode > 0.5) {
		// Multi-layer composite: near layer over far layer, output premultiplied
		// colour + alpha so the full-res composite pass blends against the base.
		out_rgb = mix(far_blur, near_blur, near_alpha);
		out_a = near_alpha + far_alpha * (1.0 - near_alpha);
	} else {
		vec3 single = (far_color + near_color - base_color) / max(far_tot + near_tot - 1.0, 0.0001);
		out_rgb = single;
		out_a = smoothstep(0.02, 0.4, max(far_mask, near_mask));
	}

	imageStore(output_image, pos, vec4(clamp(out_rgb, 0.0, 1.0), clamp(out_a, 0.0, 1.0)));
}