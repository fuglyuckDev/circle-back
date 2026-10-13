#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;

layout(push_constant, std430) uniform Params {
	float streak_threshold;
	float streak_intensity;
	float streak_length;
	float squeeze_factor;
	vec4 streak_color_core;
	vec4 streak_color_fringe;
	float dispersion;
	float lens_vignette;
	float astigmatism;
	float pad;
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

vec3 extract_highlight(vec3 col, float thresh) {
	float factor = bright_pass(col, thresh, 0.4);
	return col * factor;
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

	vec2 dist_from_center = uv - vec2(0.5);
	float dist_sq = dot(dist_from_center, dist_from_center);
	float vignette_factor = clamp(1.0 - dist_sq * params.lens_vignette * 2.0, 0.0, 1.0);

	vec3 accumulated_streak = vec3(0.0);
	float total_weight = 0.0;

	float spread_scale = params.streak_length * params.squeeze_factor * 0.5 * (1.0 + dist_sq * params.astigmatism) * 0.8;

	for (int i = -32; i <= 32; i++) {
		if (i == 0) continue;
		float fi = float(i);
		float sign_i = sign(fi);
		float abs_i = abs(fi);

		float exp_offset = sign_i * (pow(1.14, abs_i) - 1.0) * texel.x * spread_scale;

		float offset_r = exp_offset * (1.0 - params.dispersion * 0.05);
		float offset_g = exp_offset;
		float offset_b = exp_offset * (1.0 + params.dispersion * 0.05);

		vec2 uv_r = vec2(clamp(uv.x + offset_r, 0.0, 1.0), uv.y);
		vec2 uv_g = vec2(clamp(uv.x + offset_g, 0.0, 1.0), uv.y);
		vec2 uv_b = vec2(clamp(uv.x + offset_b, 0.0, 1.0), uv.y);

		vec3 sample_r = texture(input_texture, uv_r).rgb;
		vec3 sample_g = texture(input_texture, uv_g).rgb;
		vec3 sample_b = texture(input_texture, uv_b).rgb;

		vec3 isolated_r = extract_highlight(sample_r, params.streak_threshold);
		vec3 isolated_g = extract_highlight(sample_g, params.streak_threshold);
		vec3 isolated_b = extract_highlight(sample_b, params.streak_threshold);

		vec3 sample_hl = vec3(isolated_r.r, isolated_g.g, isolated_b.b);
		float kw = karis_weight(sample_hl);
		float weight = exp(-0.06 * abs_i) * kw;

		float fringe_mix = clamp(abs_i / 32.0, 0.0, 1.0);
		vec3 tint = mix(params.streak_color_core.rgb, params.streak_color_fringe.rgb, fringe_mix);

		accumulated_streak += sample_hl * tint * weight;
		total_weight += weight;
	}

	if (total_weight > 0.0) {
		accumulated_streak /= total_weight;
	}

	vec3 final_color = base_color + accumulated_streak * params.streak_intensity * vignette_factor * 1.8;
	imageStore(output_image, pos, vec4(final_color, 1.0));
}
