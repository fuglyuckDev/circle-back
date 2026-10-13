#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;
layout(set = 0, binding = 2) uniform sampler2D depth_texture;

layout(push_constant, std430) uniform Params {
	float color_levels;
	float strength;
	float dither_intensity;
	float world_scale;
	float gamma;
	float saturation_boost;
	float dither_pattern;
	float color_mode;
	float posterize_strength;
	float z_near;
	float z_far;
	float pad0;
	float pad1;
	float pad2;
	float pad3;
	float pad4;
} params;

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

float bayer8x8(ivec2 c) {
	int x = c.x & 7;
	int y = c.y & 7;
	const float m[64] = float[64](
		 0.0/64.0, 32.0/64.0,  8.0/64.0, 40.0/64.0,  2.0/64.0, 34.0/64.0, 10.0/64.0, 42.0/64.0,
		48.0/64.0, 16.0/64.0, 56.0/64.0, 24.0/64.0, 50.0/64.0, 18.0/64.0, 58.0/64.0, 26.0/64.0,
		12.0/64.0, 44.0/64.0,  4.0/64.0, 36.0/64.0, 14.0/64.0, 46.0/64.0,  6.0/64.0, 38.0/64.0,
		60.0/64.0, 28.0/64.0, 52.0/64.0, 20.0/64.0, 62.0/64.0, 30.0/64.0, 54.0/64.0, 22.0/64.0,
		 3.0/64.0, 35.0/64.0, 11.0/64.0, 43.0/64.0,  1.0/64.0, 33.0/64.0,  9.0/64.0, 41.0/64.0,
		51.0/64.0, 19.0/64.0, 59.0/64.0, 27.0/64.0, 49.0/64.0, 17.0/64.0, 57.0/64.0, 25.0/64.0,
		15.0/64.0, 47.0/64.0,  7.0/64.0, 39.0/64.0, 13.0/64.0, 45.0/64.0,  5.0/64.0, 37.0/64.0,
		63.0/64.0, 31.0/64.0, 55.0/64.0, 23.0/64.0, 61.0/64.0, 29.0/64.0, 53.0/64.0, 21.0/64.0
	);
	return m[y * 8 + x] - 0.5;
}

float bayer4x4(ivec2 c) {
	int x = c.x & 3;
	int y = c.y & 3;
	const float m[16] = float[16](
		0.0/16.0,  8.0/16.0,  2.0/16.0, 10.0/16.0,
	   12.0/16.0,  4.0/16.0, 14.0/16.0,  6.0/16.0,
		3.0/16.0, 11.0/16.0,  1.0/16.0,  9.0/16.0,
	   15.0/16.0,  7.0/16.0, 13.0/16.0,  5.0/16.0
	);
	return m[y * 4 + x] - 0.5;
}

float ign(ivec2 p) {
	vec3 magic = vec3(0.06711056, 0.00583715, 52.9829189);
	return fract(magic.z * fract(dot(vec2(p), magic.xy))) - 0.5;
}

float get_dither_val(ivec2 c) {
	if (params.dither_pattern < 0.5) return bayer8x8(c);
	if (params.dither_pattern < 1.5) return bayer4x4(c);
	return ign(c);
}

float quantize(float value, float n, float dither_offset) {
	float clamped = clamp(value, 0.0, 1.0);
	float shifted = clamp(clamped + dither_offset / n, 0.0, 1.0);
	return floor(shifted * n + 0.5) / n;
}

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(output_image);
	if (pos.x >= size.x || pos.y >= size.y) return;

	vec2 uv = (vec2(pos) + 0.5) / vec2(size);
	vec3 original = texture(input_texture, uv).rgb;
	vec3 color = original;

	if (params.color_mode > 0.5) {
		float l = luma(color);
		color = vec3(l);
	}

	float dither = get_dither_val(pos) * params.dither_intensity;

	float g = max(params.gamma, 0.01);
	vec3 gamma_corrected = pow(max(color, vec3(0.0)), vec3(1.0 / g));

	float n = max(params.color_levels, 2.0);
	vec3 posterized;
	if (params.color_mode > 0.5) {
		float ql = quantize(gamma_corrected.r, n, dither);
		posterized = vec3(ql);
	} else {
		posterized.r = quantize(gamma_corrected.r, n, dither);
		posterized.g = quantize(gamma_corrected.g, n, dither);
		posterized.b = quantize(gamma_corrected.b, n, dither);
	}

	posterized = pow(max(posterized, vec3(0.0)), vec3(g));

	if (params.saturation_boost > 0.001 && params.color_mode < 0.5) {
		float l = luma(posterized);
		posterized = mix(vec3(l), posterized, params.saturation_boost);
	}

	posterized = mix(color + (dither / n), posterized, params.posterize_strength);

	vec3 result = mix(original, posterized, params.strength);
	imageStore(output_image, pos, vec4(clamp(result, 0.0, 1.0), 1.0));
}
