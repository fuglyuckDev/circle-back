#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;

layout(push_constant, std430) uniform Params {
	float lens_blur_amount;
	float unsharp_mask_strength;
	float sharpen_threshold;
	float pad;
} params;

float luma(vec3 color) {
	return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

float karis_weight(vec3 col) {
	return 1.0 / (1.0 + luma(col));
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

	vec3 blurred = vec3(0.0);
	float total_w = 0.0;
	float scale = max(params.lens_blur_amount, 0.1);

	for (int x = -2; x <= 2; x++) {
		for (int y = -2; y <= 2; y++) {
			vec2 offset = vec2(float(x), float(y)) * texel * scale;
			vec3 s = texture(input_texture, clamp(uv + offset, vec2(0.0), vec2(1.0))).rgb;
			float kw = karis_weight(s);
			float w = exp(-0.4 * float(x * x + y * y)) * kw;
			blurred += s * w;
			total_w += w;
		}
	}
	if (total_w > 0.0) {
		blurred /= total_w;
	}

	vec3 high_pass = base_color - blurred;
	float hp_lum = abs(luma(high_pass));
	float mask = smoothstep(params.sharpen_threshold, params.sharpen_threshold + 0.1, hp_lum);

	vec3 sharpened = base_color + high_pass * params.unsharp_mask_strength * mask;

	vec3 final_color = mix(sharpened, blurred, clamp(params.lens_blur_amount * 0.2, 0.0, 1.0));
	imageStore(output_image, pos, vec4(clamp(final_color, 0.0, 1.0), 1.0));
}
