#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;

layout(push_constant, std430) uniform Params {
	float bleed_intensity;
	float bleed_radius;
	float red_bleed_shift;
	float cyan_bleed_shift;
	vec4 bleed_color;
} params;

float luma(vec3 color) {
	return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(output_image);
	if (pos.x >= size.x || pos.y >= size.y) {
		return;
	}

	vec2 uv = (vec2(pos) + vec2(0.5)) / vec2(size);
	vec2 texel = (vec2(1.0) / vec2(size)) * (float(size.y) / 1080.0);

	vec3 c_center = texture(input_texture, uv).rgb;

	// Soft multi-tap sampling for photochemical emulsion diffusion
	vec3 red_diffused = vec3(0.0);
	vec3 cyan_diffused = vec3(0.0);
	float total_weight = 0.0;

	float r_dist = params.red_bleed_shift * params.bleed_radius;
	float c_dist = params.cyan_bleed_shift * params.bleed_radius;

	for (int i = -3; i <= 3; i++) {
		float fi = float(i);
		float w = exp(-0.4 * abs(fi));

		vec2 off_r = vec2(r_dist * (1.0 + fi * 0.3) * texel.x, fi * 0.2 * texel.y);
		vec2 off_c = vec2(-c_dist * (1.0 + fi * 0.3) * texel.x, -fi * 0.2 * texel.y);

		vec3 s_r = texture(input_texture, clamp(uv + off_r, vec2(0.0), vec2(1.0))).rgb;
		vec3 s_c = texture(input_texture, clamp(uv + off_c, vec2(0.0), vec2(1.0))).rgb;

		red_diffused += s_r * w;
		cyan_diffused += s_c * w;
		total_weight += w;
	}

	if (total_weight > 0.0) {
		red_diffused /= total_weight;
		cyan_diffused /= total_weight;
	}

	// Mix displaced/diffused red & cyan emulsion layers into base color
	float mix_fac = clamp(params.bleed_intensity * 0.45, 0.0, 0.85);

	vec3 bled = vec3(
		mix(c_center.r, red_diffused.r, mix_fac),
		c_center.g,
		mix(c_center.b, cyan_diffused.b, mix_fac)
	);

	// Emulsion crosstalk (chemical layer interaction on highlights)
	float hl = smoothstep(0.4, 0.9, luma(c_center));
	float crosstalk = params.bleed_intensity * 0.12 * hl;

	bled.r += (red_diffused.g + red_diffused.b) * crosstalk;
	bled.g += (cyan_diffused.r + cyan_diffused.b) * crosstalk * 0.5;
	bled.b += (red_diffused.r + red_diffused.g) * crosstalk * 0.8;

	// Tint ONLY the bled fringe difference, preserving base image neutrals
	vec3 fringe_diff = abs(bled - c_center);
	bled += fringe_diff * (params.bleed_color.rgb - vec3(1.0)) * params.bleed_color.a;

	imageStore(output_image, pos, vec4(clamp(bled, 0.0, 1.0), 1.0));
}
