#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;

layout(push_constant, std430) uniform Params {
	float center_x;
	float center_y;
	float blur_strength;
	float sample_count;
	float blur_power;
	float pad0;
	float pad1;
	float pad2;
	float pad3;
	float pad4;
	float pad5;
	float pad6;
	float pad7;
	float pad8;
	float pad9;
	float pad10;
} params;

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

float karis_weight(vec3 c) {
	return 1.0 / (1.0 + luma(c));
}

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(output_image);
	if (pos.x >= size.x || pos.y >= size.y) return;

	vec2 uv = (vec2(pos) + 0.5) / vec2(size);
	vec2 center = vec2(params.center_x, params.center_y);

	vec2 dir = uv - center;
	float dist = length(dir);

	float strength = pow(dist, params.blur_power) * params.blur_strength * 0.1;

	int sample_num = int(max(params.sample_count, 1.0));
	vec3 result = vec3(0.0);
	float total_weight = 0.0;

	for (int i = 0; i < sample_num; i++) {
		float factor = (sample_num > 1) ? float(i) / float(sample_num - 1) : 0.0;
		float scale = 1.0 - (factor * strength);
		vec2 sample_uv = clamp(center + (dir * scale), vec2(0.0), vec2(1.0));

		vec3 s = texture(input_texture, sample_uv).rgb;
		float w = karis_weight(s);
		result += s * w;
		total_weight += w;
	}

	result /= max(total_weight, 0.0001);
	imageStore(output_image, pos, vec4(clamp(result, 0.0, 1.0), 1.0));
}
