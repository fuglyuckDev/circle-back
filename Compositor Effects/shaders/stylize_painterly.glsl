#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;

layout(push_constant, std430) uniform Params {
	float radius;
	float intensity;
	float bin_count;
	float edge_sharpness;
	float saturation_boost;
	float brush_angle;
	float brush_aspect;
	float color_variation;
	float luma_weight;
	float detail_preserve;
	float pad0;
	float pad1;
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

	int r = max(int(params.radius), 1);
	int num_bins = clamp(int(params.bin_count), 2, 32);

	float angle = params.brush_angle * (3.14159265 / 180.0);
	float ca = cos(angle), sa = sin(angle);
	float aspect = max(params.brush_aspect, 0.1);

	// Strided sampling: step by 2 for large radii, bilinear covers gaps.
	// For oil-paint histogram binning the quality difference is negligible.
	int stride = r > 3 ? 2 : 1;
	float r_sq = float(r * r);

	int bins[32];
	vec3 colors[32];
	vec3 colors_sq[32];

	for (int i = 0; i < 32; i++) {
		bins[i] = 0;
		colors[i] = vec3(0.0);
		colors_sq[i] = vec3(0.0);
	}

	for (int x = -r; x <= r; x += stride) {
		for (int y = -r; y <= r; y += stride) {
			float rx = float(x) * ca + float(y) * sa;
			float ry = -float(x) * sa + float(y) * ca;
			rx /= aspect;

			if (rx * rx + ry * ry > r_sq) continue;

			vec2 offset = vec2(float(x), float(y)) * texel;
			vec3 col = texture(input_texture, clamp(uv + offset, vec2(0.0), vec2(1.0))).rgb;

			float l = luma(col);
			int bin_idx = clamp(int(l * float(num_bins - 1) + 0.5), 0, num_bins - 1);

			bins[bin_idx] += 1;
			colors[bin_idx] += col;
			colors_sq[bin_idx] += col * col;
		}
	}

	int max_freq = 0;
	int max_bin = 0;

	for (int i = 0; i < num_bins; i++) {
		if (bins[i] > max_freq) {
			max_freq = bins[i];
			max_bin = i;
		}
	}

	vec3 oil_color = colors[max_bin] / float(max(max_freq, 1));

	if (params.color_variation > 0.001 && max_freq > 1) {
		vec3 mean = oil_color;
		vec3 mean_sq = colors_sq[max_bin] / float(max_freq);
		vec3 variance = max(mean_sq - mean * mean, vec3(0.0));
		oil_color = mix(oil_color, oil_color + sqrt(variance) * params.color_variation, 0.5);
	}

	if (params.saturation_boost != 1.0) {
		float oil_luma = luma(oil_color);
		oil_color = mix(vec3(oil_luma), oil_color, params.saturation_boost);
	}

	if (params.detail_preserve > 0.001) {
		float orig_luma = luma(original);
		float oil_luma = luma(oil_color);
		float detail = orig_luma - oil_luma;
		oil_color += vec3(detail * params.detail_preserve);
	}

	if (params.edge_sharpness > 0.001) {
		vec3 dx = texture(input_texture, clamp(uv + vec2(texel.x, 0.0), vec2(0.0), vec2(1.0))).rgb
		        - texture(input_texture, clamp(uv - vec2(texel.x, 0.0), vec2(0.0), vec2(1.0))).rgb;
		vec3 dy = texture(input_texture, clamp(uv + vec2(0.0, texel.y), vec2(0.0), vec2(1.0))).rgb
		        - texture(input_texture, clamp(uv - vec2(0.0, texel.y), vec2(0.0), vec2(1.0))).rgb;
		float edge = length(dx) + length(dy);
		float edge_mask = smoothstep(0.0, 0.3, edge);
		oil_color = mix(oil_color, original, edge_mask * params.edge_sharpness);
	}

	vec3 result = mix(original, oil_color, params.intensity);
	imageStore(output_image, pos, vec4(clamp(result, 0.0, 1.0), 1.0));
}
