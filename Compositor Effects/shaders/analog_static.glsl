#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;

layout(push_constant, std430) uniform Params {
	float intensity;
	float grain_scale;
	float monochromatic;
	float speed;
	float tint_r;
	float tint_g;
	float tint_b;
	float blend_mode;
	float shadow_response;
	float midtone_response;
	float highlight_response;
	float shadow_threshold;
	float highlight_threshold;
	float distribution;
	float clamp_output;
	float time;
} params;

uint uhash(uint x) {
	x ^= x >> 16u;
	x *= 0x45d9f3bu;
	x ^= x >> 16u;
	x *= 0x45d9f3bu;
	x ^= x >> 16u;
	return x;
}

float pixel_noise(ivec2 p, uint seed) {
	uint h = uhash(uint(p.x) + uhash(uint(p.y) + uhash(seed)));
	return float(h) / 4294967295.0;
}

vec3 pixel_noise3(ivec2 p, uint seed) {
	return vec3(
		pixel_noise(p, seed),
		pixel_noise(p, seed + 7u),
		pixel_noise(p, seed + 13u)
	);
}

float to_triangle(float u) {
	float v = u * 2.0 - 1.0;
	return sign(v) * (1.0 - sqrt(max(1.0 - abs(v), 0.0)));
}

float luminance_weight(float luma) {
	float s = 1.0 - smoothstep(0.0, params.shadow_threshold, luma);
	float h = smoothstep(params.highlight_threshold, 1.0, luma);
	float m = max(1.0 - s - h, 0.0);
	return s * params.shadow_response
	     + m * params.midtone_response
	     + h * params.highlight_response;
}

vec3 blend_screen(vec3 base_col, vec3 noise_val) {
	return 1.0 - (1.0 - base_col) * (1.0 - noise_val);
}

vec3 blend_overlay(vec3 base_col, vec3 noise_val) {
	vec3 lo = 2.0 * base_col * noise_val;
	vec3 hi = 1.0 - 2.0 * (1.0 - base_col) * (1.0 - noise_val);
	return mix(lo, hi, step(0.5, base_col));
}

vec3 blend_softlight(vec3 base_col, vec3 noise_val) {
	return (1.0 - 2.0 * noise_val) * base_col * base_col + 2.0 * noise_val * base_col;
}

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(output_image);

	if (pos.x >= size.x || pos.y >= size.y) {
		return;
	}

	vec2 uv = (vec2(pos) + vec2(0.5)) / vec2(size);
	vec3 color = texture(input_texture, uv).rgb;

	float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));

	float scale = max(params.grain_scale, 1.0);
	ivec2 gc = ivec2(floor(vec2(pos) / scale));

	uint seed = uhash(uint(params.time * 60.0 * params.speed));

	vec3 raw3 = pixel_noise3(gc, seed);
	float raw1 = pixel_noise(gc, seed + 100u);

	vec3 shaped3;
	float shaped1;
	if (params.distribution > 0.5) {
		shaped3 = vec3(to_triangle(raw3.r), to_triangle(raw3.g), to_triangle(raw3.b));
		shaped1 = to_triangle(raw1);
	} else {
		shaped3 = raw3 * 2.0 - 1.0;
		shaped1 = raw1 * 2.0 - 1.0;
	}

	float mono = params.monochromatic;
	vec3 grain = mix(shaped3, vec3(shaped1), mono);

	vec3 tint = vec3(params.tint_r, params.tint_g, params.tint_b);
	grain *= tint;

	float weight = luminance_weight(luma);
	grain *= params.intensity * weight;

	vec3 result;
	int mode = int(params.blend_mode);
	if (mode == 1) {
		vec3 noise_mapped = grain * 0.5 + 0.5;
		result = blend_screen(color, noise_mapped * params.intensity * weight);
		result = mix(color, result, params.intensity);
	} else if (mode == 2) {
		vec3 noise_mapped = grain * 0.5 + 0.5;
		result = blend_overlay(color, noise_mapped);
	} else if (mode == 3) {
		vec3 noise_mapped = grain * 0.5 + 0.5;
		result = blend_softlight(color, noise_mapped);
	} else {
		result = color + grain;
	}

	if (params.clamp_output > 0.5) {
		result = clamp(result, vec3(0.0), vec3(1.0));
	} else {
		result = max(result, vec3(0.0));
	}

	imageStore(output_image, pos, vec4(result, 1.0));
}
