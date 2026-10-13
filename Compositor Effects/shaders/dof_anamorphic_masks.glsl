#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D depth_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;

layout(push_constant, std430) uniform Params {
	float focus_distance;
	float in_focus_width;
	float near_range;
	float far_range;
	float falloff;
	float bokeh_radius_far;
	float bokeh_radius_near;
	float z_near;
	float z_far;
	float use_physical;
	float pad0;
	float pad1;
	float pad2;
	float pad3;
	float pad4;
	float pad5;
} params;

float linearize_depth(float raw) {
	float n = params.z_near;
	float f = params.z_far;
	return (n * f) / (n + raw * (f - n));
}

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

// Screen-space blur of the far/near CoC masks (5-tap Gaussian separable) so the
// depth-side transition ramps gradually and silhouettes never leave hard steps.
vec2 smooth_masks(vec2 uv, vec2 texel, float step_px) {
	float c0 = compute_coc(linearize_depth(texture(depth_texture, uv).r));
	vec2 m = vec2(max(c0, 0.0), max(-c0, 0.0)) * 6.0; // weights 1-4-6-4-1
	float wsum = 6.0;
	for (int axis = 0; axis < 2; axis++) {
		for (int i = 1; i <= 2; i++) {
			vec2 off = vec2(axis == 0 ? 1.0 : 0.0, axis == 1 ? 1.0 : 0.0) * (step_px * texel) * float(i);
			float w = (i == 1) ? 4.0 : 1.0;
			float ca = compute_coc(linearize_depth(texture(depth_texture, clamp(uv + off, vec2(0.0), vec2(1.0))).r));
			float cb = compute_coc(linearize_depth(texture(depth_texture, clamp(uv - off, vec2(0.0), vec2(1.0))).r));
			m.x += w * (max(ca, 0.0) + max(cb, 0.0));
			m.y += w * (max(-ca, 0.0) + max(-cb, 0.0));
			wsum += 2.0 * w;
		}
	}
	return m / wsum;
}

// Dilate the far/near masks over a ring so each blurred layer covers its disc
// footprint (lets a blurred foreground smear over the background).
vec2 dilate_masks(vec2 uv, vec2 texel, float rad_px) {
	vec2 m = vec2(0.0);
	const int n = 24;
	for (int i = 0; i < n; i++) {
		float a = float(i) / float(n) * 6.28318530718;
		vec2 off = vec2(cos(a), sin(a)) * (rad_px * texel);
		float c = compute_coc(linearize_depth(texture(depth_texture, clamp(uv + off, vec2(0.0), vec2(1.0))).r));
		m.x = max(m.x, max(c, 0.0));
		m.y = max(m.y, max(-c, 0.0));
	}
	return m;
}

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(output_image);
	if (pos.x >= size.x || pos.y >= size.y) return;

	vec2 size_f = vec2(size);
	vec2 uv = (vec2(pos) + 0.5) / size_f;
	vec2 texel = (vec2(1.0) / size_f) * (float(size.y) / 1080.0);

	// Dilated abs CoC (3x3 max) for the gathering radius.
	float radius_coc = abs(compute_coc(linearize_depth(texture(depth_texture, uv).r)));
	for (int dy = -1; dy <= 1; dy++) {
		for (int dx = -1; dx <= 1; dx++) {
			if (dx == 0 && dy == 0) continue;
			vec2 nuv = clamp(uv + (vec2(float(dx), float(dy)) / size_f), vec2(0.0), vec2(1.0));
			radius_coc = max(radius_coc, abs(compute_coc(linearize_depth(texture(depth_texture, nuv).r))));
		}
	}
	float max_blur = radius_coc * max(params.bokeh_radius_far, params.bokeh_radius_near);

	// Ring-dilate the radius over the same footprint as the masks so the gather
	// always searches far enough to cover the largest disc overlapping this pixel
	// — without this the blurred layer's edge cuts hard at the disc boundary.
	{
		const int rn = 24;
		for (int i = 0; i < rn; i++) {
			float a = float(i) / float(rn) * 6.28318530718;
			vec2 off = vec2(cos(a), sin(a)) * (max_blur * 0.75 * texel);
			float c = abs(compute_coc(linearize_depth(texture(depth_texture, clamp(uv + off, vec2(0.0), vec2(1.0))).r)));
			radius_coc = max(radius_coc, c);
		}
	}

	float falloff_px = mix(1.0, 12.0, params.falloff);
	vec2 sm = smooth_masks(uv, texel, falloff_px);
	vec2 dl = dilate_masks(uv, texel, max_blur * 0.75);
	vec2 masks = max(sm, dl);

	// r = far mask, g = near mask, b = ring-dilated radius. The mask blur passes
	// feather this texture afterwards so the dilation edge is never hard.
	imageStore(output_image, pos, vec4(masks.x, masks.y, radius_coc, 1.0));
}