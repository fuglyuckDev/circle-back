#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;

layout(push_constant, std430) uniform Params {
	float pixel_size_x;
	float pixel_size_y;
	float grid_offset_x;
	float grid_offset_y;
	float gap_size_x;
	float gap_size_y;
	float gap_color_r;
	float gap_color_g;
	float gap_color_b;
	float gap_roundness;
	float gap_aa;
	float color_mode;
	float posterize_levels;
	float outline_strength;
	float outline_threshold;
	float strength;
} params;

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(output_image);
	if (pos.x >= size.x || pos.y >= size.y) return;

	vec2 uv = (vec2(pos) + 0.5) / vec2(size);
	vec3 original = texture(input_texture, uv).rgb;

	int px = max(int(params.pixel_size_x), 1);
	int py = max(int(params.pixel_size_y), 1);

	vec2 offset = vec2(params.grid_offset_x, params.grid_offset_y);
	vec2 p = vec2(pos) - offset;
	vec2 cell = floor(p / vec2(px, py));
	vec2 local_pos = p - cell * vec2(px, py);

	float gap_x = clamp(params.gap_size_x, 0.0, float(px) - 1.0);
	float gap_y = clamp(params.gap_size_y, 0.0, float(py) - 1.0);
	float fill_w = float(px) - gap_x;
	float fill_h = float(py) - gap_y;
	vec2 fill_center = vec2(fill_w, fill_h) * 0.5;

	float in_gap = 0.0;
	float roundness = clamp(params.gap_roundness, 0.0, 1.0);
	float aa = max(params.gap_aa, 0.01);

	if (gap_x > 0.0 || gap_y > 0.0) {
		vec2 fill_half = vec2(fill_w, fill_h) * 0.5;
		float max_radius = min(fill_half.x, fill_half.y);
		float radius = roundness * max_radius;
		vec2 d = abs(local_pos - fill_center) - fill_half + vec2(radius);
		float sdf = length(max(d, vec2(0.0))) - radius;
		in_gap = smoothstep(-aa, aa, sdf);
	}

	vec2 snapped_uv = (cell * vec2(px, py) + vec2(float(px) * 0.5, float(py) * 0.5) + offset) / vec2(size);
	snapped_uv = clamp(snapped_uv, vec2(0.0), vec2(1.0));
	vec3 pixel_color = texture(input_texture, snapped_uv).rgb;

	int mode = int(params.color_mode);
	if (mode == 1) {
		float l = luma(pixel_color);
		pixel_color = vec3(l);
	} else if (mode == 2) {
		pixel_color = vec3(
			pixel_color.r > 0.5 ? 1.0 : 0.0,
			pixel_color.g > 0.5 ? 1.0 : 0.0,
			pixel_color.b > 0.5 ? 1.0 : 0.0
		);
	}

	float levels = params.posterize_levels;
	if (levels > 1.5 && levels < 256.0) {
		pixel_color = floor(pixel_color * levels + 0.5) / levels;
	}

	if (params.outline_strength > 0.001) {
		vec2 texel = (1.0 / vec2(size)) * vec2(float(px), float(py));
		vec2 neighbor_offsets[4] = vec2[4](
			vec2(texel.x, 0.0), vec2(-texel.x, 0.0),
			vec2(0.0, texel.y), vec2(0.0, -texel.y)
		);
		float edge = 0.0;
		float center_luma = luma(pixel_color);
		for (int i = 0; i < 4; i++) {
			vec2 nuv = clamp(snapped_uv + neighbor_offsets[i], vec2(0.0), vec2(1.0));
			float nl = luma(texture(input_texture, nuv).rgb);
			edge += abs(center_luma - nl);
		}
		edge *= 0.25;
		float outline = smoothstep(params.outline_threshold, params.outline_threshold + 0.1, edge);
		pixel_color *= 1.0 - outline * params.outline_strength;
	}

	vec3 gap_col = vec3(params.gap_color_r, params.gap_color_g, params.gap_color_b);
	vec3 result = mix(pixel_color, gap_col, in_gap);
	result = mix(original, result, params.strength);

	imageStore(output_image, pos, vec4(clamp(result, 0.0, 1.0), 1.0));
}
