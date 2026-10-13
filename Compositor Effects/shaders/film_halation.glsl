#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;

layout(push_constant, std430) uniform Params {
	float halation_threshold;
	float halation_intensity;
	float halation_spread;
	float time;
	vec4 halation_color;
	float glow_intensity;
	float glow_spread;
	float film_shoulder_rolloff;
	float glow_horizontal_stretch;
	vec4 glow_tint;
	float animation_intensity;
	int pass_mode;
	int pad0;
	int pad1;
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

vec3 apply_film_shoulder(vec3 col, float shoulder) {
	return col / (vec3(1.0) + col / shoulder);
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

	float h_stretch = max(params.glow_horizontal_stretch, 0.1);
	vec2 dir = (params.pass_mode == 0) ? vec2(h_stretch, 0.0) : vec2(0.0, 1.0);

	vec3 accumulated_halation = vec3(0.0);
	float halation_weight = 0.0;
	float h_sigma = max(params.halation_spread * 1.5, 1.0);

	for (int i = -16; i <= 16; i++) {
		float fi = float(i);
		float sign_i = (fi < 0.0) ? -1.0 : 1.0;
		float abs_i = abs(fi);

		float step_offset = sign_i * abs_i * (1.0 + abs_i * 0.03 * params.halation_spread);
		vec2 offset = dir * step_offset * texel;
		vec2 sample_uv = clamp(uv + offset, vec2(0.0), vec2(1.0));

		vec3 s_h = texture(input_texture, sample_uv).rgb;
		float factor_h = (params.pass_mode == 0) ? bright_pass(s_h, params.halation_threshold, 0.4) : 1.0;
		float kw = karis_weight(s_h);
		float w = exp(-(abs_i * abs_i) / (2.0 * h_sigma * h_sigma)) * kw;

		accumulated_halation += s_h.r * factor_h * params.halation_color.rgb * w;
		halation_weight += w;
	}

	if (halation_weight > 0.0) {
		accumulated_halation /= halation_weight;
	}

	vec3 accumulated_glow = vec3(0.0);
	float glow_weight = 0.0;
	float g_sigma = max(params.glow_spread * 2.0, 1.5);

	for (int j = -24; j <= 24; j++) {
		float fj = float(j);
		float sign_j = (fj < 0.0) ? -1.0 : 1.0;
		float abs_j = abs(fj);

		float step_offset = sign_j * abs_j * (1.0 + abs_j * 0.04 * params.glow_spread);
		vec2 offset = dir * step_offset * texel;
		vec2 sample_uv = clamp(uv + offset, vec2(0.0), vec2(1.0));

		vec3 s_g = texture(input_texture, sample_uv).rgb;
		float factor_g = (params.pass_mode == 0) ? bright_pass(s_g, 0.45, 0.6) : 1.0;
		float kw = karis_weight(s_g);
		float w = exp(-(abs_j * abs_j) / (2.0 * g_sigma * g_sigma)) * kw;

		accumulated_glow += s_g * factor_g * params.glow_tint.rgb * w;
		glow_weight += w;
	}

	if (glow_weight > 0.0) {
		accumulated_glow /= glow_weight;
	}

	// Base static halation and glow (never scaled down by animation_intensity)
	vec3 base_halation_glow = accumulated_halation * params.halation_intensity + accumulated_glow * params.glow_intensity;

	// Dynamic breathing pulse layer on top (controlled by animation_intensity)
	float breathe_pulse = sin(params.time * 6.0) * 0.15 * params.animation_intensity;

	vec3 combined = base_color + base_halation_glow * (1.0 + breathe_pulse);
	if (params.pass_mode == 1) {
		combined = apply_film_shoulder(combined, params.film_shoulder_rolloff);
	}

	imageStore(output_image, pos, vec4(clamp(combined, 0.0, 1.0), 1.0));
}
