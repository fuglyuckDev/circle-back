#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;

layout(push_constant, std430) uniform Params {
	float strength;
	float temperature;
	float tint;
	float gain_r;
	float gain_g;
	float gain_b;
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
} params;

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(output_image);
	if (pos.x >= size.x || pos.y >= size.y) return;

	vec2 uv = (vec2(pos) + 0.5) / vec2(size);
	vec3 color = texture(input_texture, uv).rgb;

	// Temperature: + = warm (boost R, cut B), - = cool.
	float t = clamp(params.temperature, -1.0, 1.0) * 0.2;
	vec3 warm = vec3(1.0 + t, 1.0, 1.0 - t);

	// Tint: + = magenta (boost R/B, cut G), - = green.
	float m = clamp(params.tint, -1.0, 1.0) * 0.15;
	vec3 tintf = vec3(1.0 + m, 1.0 - m, 1.0 + m);

	vec3 modified = color * warm * tintf * vec3(params.gain_r, params.gain_g, params.gain_b);

	vec3 result = mix(color, modified, clamp(params.strength, 0.0, 1.0));
	imageStore(output_image, pos, vec4(clamp(result, 0.0, 1.0), 1.0));
}