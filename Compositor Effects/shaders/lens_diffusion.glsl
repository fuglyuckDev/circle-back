#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;

layout(push_constant, std430) uniform Params {
	float diffusion_intensity;
	float diffusion_radius;
	float fog_density;
	float contrast_preservation;
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

	vec2 dir = (params.pass_mode == 0) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);

	vec3 accumulated_diffusion = vec3(0.0);
	float total_weight = 0.0;

	float r_scale = max(params.diffusion_radius, 0.5);
	float sigma = r_scale * 2.0;

	// Dual-Pass Separable Gaussian Convolution on Isolated Highlights
	for (int i = -24; i <= 24; i++) {
		float fi = float(i);
		float sign_i = (fi < 0.0) ? -1.0 : 1.0;
		float abs_i = abs(fi);

		float step_offset = sign_i * abs_i * (1.0 + abs_i * 0.025 * r_scale);
		vec2 offset = dir * step_offset * texel;
		vec2 sample_uv = clamp(uv + offset, vec2(0.0), vec2(1.0));

		vec3 sample_col = texture(input_texture, sample_uv).rgb;

		// Extract specular highlights (Pro-Mist selective diffusion)
		float hl_factor = (params.pass_mode == 0) ? bright_pass(sample_col, 0.35, 0.5) : 1.0;
		float kw = karis_weight(sample_col);
		float w = exp(-(abs_i * abs_i) / (2.0 * sigma * sigma)) * kw;

		accumulated_diffusion += sample_col * hl_factor * w;
		total_weight += w;
	}

	if (total_weight > 0.0) {
		accumulated_diffusion /= total_weight;
	}

	// Photochemical Screen / Additive blending onto sharp base image
	vec3 mist = accumulated_diffusion * params.tint_color.rgb * params.diffusion_intensity * 1.6;

	// Black Pro-Mist contrast preservation (Shadow protection rule)
	float shadow_preservation = mix(1.0, smoothstep(0.02, 0.3, luma(base_color)), params.contrast_preservation);

	// Screen blend mode preserves 100% sharp base image details while highlights bloom out
	vec3 diffused_result = 1.0 - (1.0 - base_color) * (1.0 - mist * shadow_preservation);

	// Optional atmospheric mist overlay
	if (params.fog_density > 0.001) {
		diffused_result = mix(diffused_result, params.tint_color.rgb, params.fog_density * 0.15);
	}

	imageStore(output_image, pos, vec4(clamp(diffused_result, 0.0, 1.0), 1.0));
}
