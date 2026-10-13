#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;

layout(push_constant, std430) uniform Params {
	float blur_radius;
	float blur_sigma;
	float direction_x;
	float direction_y;
	float strength;
	float preserve_alpha;
	float luminance_mask;
	float mask_invert;
	float mask_threshold;
	float mask_softness;
	float tint_r;
	float tint_g;
	float tint_b;
	float gamma_correct;
	float pad0;
	float pad1;
} params;

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

float karis_weight(vec3 c) {
	return 1.0 / (1.0 + luma(c));
}

float gaussian(float x, float sigma) {
	return exp(-(x * x) / (2.0 * sigma * sigma));
}

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(output_image);
	if (pos.x >= size.x || pos.y >= size.y) return;

	vec2 uv = (vec2(pos) + 0.5) / vec2(size);
	vec2 texel = (vec2(1.0) / vec2(size)) * (float(size.y) / 1080.0);
	vec3 original = texture(input_texture, uv).rgb;

	int radius = clamp(int(params.blur_radius), 0, 32);

	if (radius == 0 || params.strength < 0.001) {
		imageStore(output_image, pos, vec4(original, 1.0));
		return;
	}

	float sigma = params.blur_sigma > 0.001 ? params.blur_sigma : float(radius) / 3.0;
	vec2 dir = vec2(params.direction_x, params.direction_y);

	vec3 accum = vec3(0.0);
	float weight_sum = 0.0;

	for (int i = -radius; i <= radius; i++) {
		vec2 offset = dir * float(i) * texel;
		vec2 sample_uv = clamp(uv + offset, vec2(0.0), vec2(1.0));
		vec3 s = texture(input_texture, sample_uv).rgb;

		if (params.gamma_correct > 0.5) {
			s = s * s;
		}

		float w = gaussian(float(i), sigma) * karis_weight(s);
		accum += s * w;
		weight_sum += w;
	}

	vec3 blurred = accum / max(weight_sum, 0.0001);

	if (params.gamma_correct > 0.5) {
		blurred = sqrt(max(blurred, vec3(0.0)));
	}

	vec3 tint = vec3(params.tint_r, params.tint_g, params.tint_b);
	blurred *= tint;

	float local_strength = params.strength;

	if (params.luminance_mask > 0.5) {
		float l = luma(original);
		float mask = smoothstep(params.mask_threshold, params.mask_threshold + max(params.mask_softness, 0.001), l);
		if (params.mask_invert > 0.5) mask = 1.0 - mask;
		local_strength *= mask;
	}

	vec3 result = mix(original, blurred, local_strength);
	imageStore(output_image, pos, vec4(clamp(result, 0.0, 1.0), 1.0));
}
