#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;

layout(push_constant, std430) uniform Params {
	float brush_radius;
	float pigment_bleed;
	float strength;
	float edge_preservation;
	float luma_preservation;
	float color_boost;
	float shape;
	float bleed_threshold;
	float pad0;
	float pad1;
	float pad2;
	float pad3;
	float pad4;
	float pad5;
	float pad6;
	float pad7;
} params;

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(output_image);
	if (pos.x >= size.x || pos.y >= size.y) return;

	vec2 uv = (vec2(pos) + 0.5) / vec2(size);
	vec2 texel = (vec2(1.0) / vec2(size)) * (float(size.y) / 1080.0);
	vec3 original = texture(input_texture, uv).rgb;

	int radius = max(int(params.brush_radius), 1);

	// Strided sampling: step by 2 for radii > 3, letting bilinear filter cover gaps.
	// This reduces sample count by ~4x with imperceptible quality loss for painterly effects.
	int stride = radius > 3 ? 2 : 1;

	vec3 m[4];
	vec3 s[4];
	for (int k = 0; k < 4; k++) {
		m[k] = vec3(0.0);
		s[k] = vec3(0.0);
	}

	// Quadrant offsets: TL, TR, BL, BR
	ivec2 offsets[4] = ivec2[](
		ivec2(-radius, -radius),
		ivec2(0, -radius),
		ivec2(-radius, 0),
		ivec2(0, 0)
	);

	float half_r = float(radius) * 0.5;
	bool circular = params.shape > 0.5;

	for (int q = 0; q < 4; q++) {
		int n = 0;
		for (int x = 0; x <= radius; x += stride) {
			for (int y = 0; y <= radius; y += stride) {
				if (circular) {
					vec2 diff = vec2(float(x), float(y)) - vec2(half_r);
					if (dot(diff, diff) > (half_r + 0.5) * (half_r + 0.5)) continue;
				}

				vec2 offset = (vec2(offsets[q]) + vec2(float(x), float(y))) * texel;
				vec3 c = texture(input_texture, clamp(uv + offset, vec2(0.0), vec2(1.0))).rgb;
				m[q] += c;
				s[q] += c * c;
				n++;
			}
		}
		float inv_n = 1.0 / float(max(n, 1));
		m[q] *= inv_n;
		s[q] = abs(s[q] * inv_n - m[q] * m[q]);
	}

	float min_var = 1e6;
	vec3 w_color = vec3(0.0);

	for (int q = 0; q < 4; q++) {
		float variance = dot(s[q], vec3(1.0));
		if (variance < min_var) {
			min_var = variance;
			w_color = m[q];
		}
	}

	vec3 final_color = w_color;

	if (params.pigment_bleed > 0.0) {
		float edge_val = clamp(min_var * 50.0 / max(params.bleed_threshold, 0.001), 0.0, 1.0);
		final_color *= mix(1.0, 0.5, edge_val * params.pigment_bleed);
	}

	if (params.color_boost > 0.001) {
		float l = luma(final_color);
		final_color = mix(final_color, mix(vec3(l), final_color, 1.0 + params.color_boost), 1.0);
	}

	if (params.luma_preservation > 0.0) {
		float luma_orig = luma(original);
		float luma_final = luma(final_color);
		final_color *= mix(1.0, luma_orig / max(luma_final, 0.0001), params.luma_preservation);
	}

	vec3 result = mix(original, final_color, params.strength);
	imageStore(output_image, pos, vec4(clamp(result, 0.0, 1.0), 1.0));
}
