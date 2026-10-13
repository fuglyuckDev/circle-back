#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(set = 0, binding = 1) uniform sampler2D ghost_texture;
layout(rgba16f, set = 0, binding = 2) uniform writeonly image2D output_image;

layout(push_constant, std430) uniform Params {
	float strength;
	float trail_mix;
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
	float pad12;
	float pad13;
} params;

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(output_image);
	if (pos.x >= size.x || pos.y >= size.y) return;

	vec2 uv = (vec2(pos) + 0.5) / vec2(size);
	vec3 color = texture(input_texture, uv).rgb;
	vec3 ghost = texture(ghost_texture, uv).rgb;

	vec3 result = mix(color, ghost, clamp(params.trail_mix * params.strength, 0.0, 1.0));
	imageStore(output_image, pos, vec4(clamp(result, 0.0, 1.0), 1.0));
}