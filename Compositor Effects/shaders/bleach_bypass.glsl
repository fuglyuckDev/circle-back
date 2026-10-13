#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;

layout(push_constant, std430) uniform Params {
	float strength;
	float saturation_boost;
	float contrast;
	float exposure;
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
	float pad11;
} params;

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(output_image);
	if (pos.x >= size.x || pos.y >= size.y) return;

	vec2 uv = (vec2(pos) + vec2(0.5)) / vec2(size);
	vec3 color = texture(input_texture, uv).rgb * params.exposure;

	float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
	vec3 blend = vec3(luma);

	vec3 bypass = vec3(0.0);
	for (int i = 0; i < 3; i++) {
		if (blend[i] < 0.5) {
			bypass[i] = 2.0 * color[i] * blend[i];
		} else {
			bypass[i] = 1.0 - 2.0 * (1.0 - color[i]) * (1.0 - blend[i]);
		}
	}

	vec3 mixed = mix(color, bypass, params.strength);

	if (params.saturation_boost > 0.001) {
		float mix_luma = dot(mixed, vec3(0.2126, 0.7152, 0.0722));
		mixed = mix(vec3(mix_luma), mixed, 1.0 + params.saturation_boost);
	}

	if (params.contrast != 1.0) {
		mixed = (mixed - 0.5) * max(params.contrast, 0.0) + 0.5;
	}

	mixed = max(mixed, vec3(0.0));
	imageStore(output_image, pos, vec4(mixed, 1.0));
}
