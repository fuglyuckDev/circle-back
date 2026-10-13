#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;

layout(push_constant, std430) uniform Params {
	float inner_radius;
	float blur_falloff;
	float bokeh_squeeze_ratio;
	float bokeh_intensity;
	float bokeh_max_radius;
	float bokeh_threshold;
	float cats_eye_strength;
	float edge_swirl_strength;
} params;

float luma(vec3 color) {
	return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

float karis_weight(vec3 col) {
	return 1.0 / (1.0 + luma(col));
}

float bright_pass(vec3 color, float mask_threshold, float mask_knee) {
	return smoothstep(mask_threshold, mask_threshold + mask_knee, luma(color));
}

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(output_image);
	if (pos.x >= size.x || pos.y >= size.y) {
		return;
	}

	vec2 uv = (vec2(pos) + vec2(0.5)) / vec2(size);
	vec2 texel = (vec2(1.0) / vec2(size)) * (float(size.y) / 1080.0);
	vec3 base_color = texture(input_texture, uv).rgb;

	vec2 aspect = vec2(float(size.x) / float(size.y), 1.0);
	vec2 uvd = (uv - vec2(0.5)) * aspect;
	float dist = length(uvd);
	float dist_sq = dot(uvd, uvd);

	float coc = smoothstep(params.inner_radius, params.inner_radius + params.blur_falloff, dist);

	if (coc <= 0.001) {
		imageStore(output_image, pos, vec4(base_color, 1.0));
		return;
	}

	// Anamorphic cat's eye lens vignetting & field curvature squeeze
	float edge_vignette = dist_sq * params.cats_eye_strength * 4.0;
	vec2 oval_scale = vec2(1.0 / max(params.bokeh_squeeze_ratio + edge_vignette, 0.5), 1.0);

	// Anamorphic optical radial swirl & angle tilt
	float swirl_tilt = dist_sq * params.edge_swirl_strength * 1.5;
	float cos_t = cos(swirl_tilt);
	float sin_t = sin(swirl_tilt);

	vec3 accumulated_bokeh = vec3(0.0);
	float total_weight = 0.0;
	float golden_angle = 2.39996323;
	float radius = coc * params.bokeh_max_radius;

	for (int i = 1; i <= 64; i++) {
		float fi = float(i);
		float r = sqrt(fi / 64.0) * radius;
		float angle = fi * golden_angle;

		vec2 sample_dir = vec2(cos(angle), sin(angle)) * oval_scale;

		vec2 rotated_sample = vec2(
			sample_dir.x * cos_t - sample_dir.y * sin_t,
			sample_dir.x * sin_t + sample_dir.y * cos_t
		);

		vec2 offset = rotated_sample * texel * r * 1.5;

		vec2 sample_uv = clamp(uv + offset, vec2(0.0), vec2(1.0));
		vec3 s_col = texture(input_texture, sample_uv).rgb;

		float hl_factor = bright_pass(s_col, params.bokeh_threshold, 0.4);
		float kw = karis_weight(s_col);
		float w = (1.0 + hl_factor * params.bokeh_intensity * 3.0) * kw;

		accumulated_bokeh += s_col * w;
		total_weight += w;
	}

	if (total_weight > 0.0) {
		accumulated_bokeh /= total_weight;
	}

	vec3 final_color = mix(base_color, accumulated_bokeh, coc);
	imageStore(output_image, pos, vec4(clamp(final_color, 0.0, 1.0), 1.0));
}
