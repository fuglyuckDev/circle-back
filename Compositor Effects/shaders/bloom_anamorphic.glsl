#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;

layout(push_constant, std430) uniform Params {
	float bloom_intensity;
	float bloom_threshold;
	float anamorphic_spread;
	float aspect_stretch;
	float film_shoulder;
	float bloom_angle;
	float pad0;
	float pad1;
	vec4 bloom_color;
	int pass_mode;
	int pad3;
	int pad4;
	int pad5;
} params;

float luma(vec3 color) {
	return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

float karis_weight(vec3 col) {
	return 1.0 / (1.0 + luma(col));
}

float bright_pass(vec3 color, float mask_threshold, float mask_knee) {
	float lum = luma(color);
	float luma_pass = smoothstep(mask_threshold, mask_threshold + mask_knee, lum);
	float max_c = max(color.r, max(color.g, color.b));
	float min_c = min(color.r, min(color.g, color.b));
	float sat = max_c - min_c;
	float chroma_pass = smoothstep(0.35, 0.65, sat);
	return max(luma_pass, chroma_pass * 0.5);
}

vec3 apply_film_shoulder(vec3 col, float shoulder) {
	return col / (vec3(1.0) + col / max(shoulder, 0.01));
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

	float angle_rad = radians(params.bloom_angle);
	float perp_rad = angle_rad + radians(90.0);
	vec2 primary_dir = vec2(cos(angle_rad), sin(angle_rad));
	vec2 perp_dir = vec2(cos(perp_rad), sin(perp_rad));

	vec2 dir = (params.pass_mode == 0)
		? primary_dir * max(params.aspect_stretch, 1.0)
		: perp_dir * 0.35;

	vec3 accumulated_bloom = vec3(0.0);
	float total_weight = 0.0;
	float sigma = max(params.anamorphic_spread * 1.8, 1.0);

	for (int i = -32; i <= 32; i++) {
		float fi = float(i);
		float sign_i = (fi < 0.0) ? -1.0 : 1.0;
		float abs_i = abs(fi);

		float step_offset = sign_i * abs_i * (1.0 + abs_i * 0.03 * params.anamorphic_spread);
		vec2 offset = dir * step_offset * texel;
		vec2 sample_uv = clamp(uv + offset, vec2(0.0), vec2(1.0));

		vec3 sample_col = texture(input_texture, sample_uv).rgb;
		float factor = (params.pass_mode == 0) ? bright_pass(sample_col, params.bloom_threshold, 0.5) : 1.0;
		float kw = karis_weight(sample_col);

		float w = exp(-(abs_i * abs_i) / (2.0 * sigma * sigma)) * kw;

		accumulated_bloom += sample_col * factor * params.bloom_color.rgb * w;
		total_weight += w;
	}

	if (total_weight > 0.0) {
		accumulated_bloom /= total_weight;
	}

	vec3 combined = base_color + accumulated_bloom * params.bloom_intensity * 1.5;

	if (params.pass_mode == 1 && params.film_shoulder > 0.001) {
		combined = apply_film_shoulder(combined, params.film_shoulder);
	}

	imageStore(output_image, pos, vec4(clamp(combined, 0.0, 1.0), 1.0));
}
