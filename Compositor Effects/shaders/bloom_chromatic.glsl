#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;

layout(push_constant, std430) uniform Params {
	float bloom_intensity;
	float bloom_threshold;
	float dispersion_spread;
	float spectral_separation;
	vec4 tint_color;
	int pass_mode;
	int pad0;
	int pad1;
	int pad2;
} params;

float luma(vec3 color) {
	return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

float karis_weight(vec3 col) {
	return 1.0 / (1.0 + luma(col));
}

float bright_pass(vec3 color, float mask_threshold, float mask_knee) {
	float lum = luma(color);
	float luma_pass = smoothstep(mask_threshold, mask_threshold + mask_knee, lum);
	float max_c = max(color.r, max(color.g, color.b));
	float min_c = min(color.r, min(color.g, color.b));
	float sat = max_c - min_c;
	float chroma_pass = smoothstep(0.35, 0.65, sat);
	return max(luma_pass, chroma_pass * 0.5);
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

	vec2 dir = (params.pass_mode == 0) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);

	vec3 accumulated_chroma = vec3(0.0);
	float total_weight = 0.0;
	float sigma = max(params.dispersion_spread * 1.6, 1.0);

	float r_mult = 1.0 + params.spectral_separation * 0.4;
	float g_mult = 1.0;
	float b_mult = 1.0 - params.spectral_separation * 0.3;

	for (int i = -24; i <= 24; i++) {
		float fi = float(i);
		float sign_i = (fi < 0.0) ? -1.0 : 1.0;
		float abs_i = abs(fi);

		float step_offset = sign_i * abs_i * (1.0 + abs_i * 0.03 * params.dispersion_spread);

		vec2 off_r = dir * step_offset * r_mult * texel;
		vec2 off_g = dir * step_offset * g_mult * texel;
		vec2 off_b = dir * step_offset * b_mult * texel;

		vec3 s_r = texture(input_texture, clamp(uv + off_r, vec2(0.0), vec2(1.0))).rgb;
		vec3 s_g = texture(input_texture, clamp(uv + off_g, vec2(0.0), vec2(1.0))).rgb;
		vec3 s_b = texture(input_texture, clamp(uv + off_b, vec2(0.0), vec2(1.0))).rgb;

		float factor_r = (params.pass_mode == 0) ? bright_pass(s_r, params.bloom_threshold, 0.4) : 1.0;
		float factor_g = (params.pass_mode == 0) ? bright_pass(s_g, params.bloom_threshold, 0.4) : 1.0;
		float factor_b = (params.pass_mode == 0) ? bright_pass(s_b, params.bloom_threshold, 0.4) : 1.0;

		vec3 s_combined = vec3(s_r.r * factor_r, s_g.g * factor_g, s_b.b * factor_b);
		float kw = karis_weight(s_combined);

		float w = exp(-(abs_i * abs_i) / (2.0 * sigma * sigma)) * kw;

		accumulated_chroma += s_combined * w;
		total_weight += w;
	}

	if (total_weight > 0.0) {
		accumulated_chroma /= total_weight;
	}

	vec3 final_color = base_color + accumulated_chroma * params.bloom_intensity * params.tint_color.rgb * 1.5;
	imageStore(output_image, pos, vec4(clamp(final_color, 0.0, 1.0), 1.0));
}
