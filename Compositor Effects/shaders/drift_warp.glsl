#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;

layout(push_constant, std430) uniform Params {
	float strength;
	float amplitude;
	float frequency;
	float speed;
	float time;
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

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(output_image);
	if (pos.x >= size.x || pos.y >= size.y) return;

	vec2 uv = (vec2(pos) + 0.5) / vec2(size);
	vec2 texel = (vec2(1.0) / vec2(size)) * (float(size.y) / 1080.0);
	vec3 color = texture(input_texture, uv).rgb;

	float a = params.amplitude * texel.x;
	float f = max(params.frequency, 0.001);
	float w = params.time * params.speed;

	// Two-octave breathing warp (dreamlike "the world breathes").
	vec2 warp = vec2(
		sin(uv.y * f + w) * a + sin(uv.x * f * 2.0 + w * 1.7) * a * 0.5,
		cos(uv.x * f * 0.7 + w * 0.8) * a + cos(uv.y * f * 1.5 + w * 1.3) * a * 0.5
	);

	vec3 modified = texture(input_texture, clamp(uv + warp, vec2(0.0), vec2(1.0))).rgb;

	vec3 result = mix(color, modified, clamp(params.strength, 0.0, 1.0));
	imageStore(output_image, pos, vec4(clamp(result, 0.0, 1.0), 1.0));
}