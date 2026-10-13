#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;

layout(push_constant, std430) uniform Params {
	vec2 inv_tex_size;
	float pad0;
	float pad1;
} params;

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(output_image);
	if (pos.x >= size.x || pos.y >= size.y) return;

	vec2 norm_uv = (vec2(pos) + 0.5) / vec2(size);
	vec2 texel = params.inv_tex_size;

	vec3 A = texture(input_texture, norm_uv + vec2(-2.0, -2.0) * texel).rgb;
	vec3 B = texture(input_texture, norm_uv + vec2( 0.0, -2.0) * texel).rgb;
	vec3 C = texture(input_texture, norm_uv + vec2( 2.0, -2.0) * texel).rgb;
	vec3 D = texture(input_texture, norm_uv + vec2(-2.0,  0.0) * texel).rgb;
	vec3 E = texture(input_texture, norm_uv + vec2( 0.0,  0.0) * texel).rgb;
	vec3 F = texture(input_texture, norm_uv + vec2( 2.0,  0.0) * texel).rgb;
	vec3 G = texture(input_texture, norm_uv + vec2(-2.0,  2.0) * texel).rgb;
	vec3 H = texture(input_texture, norm_uv + vec2( 0.0,  2.0) * texel).rgb;
	vec3 I = texture(input_texture, norm_uv + vec2( 2.0,  2.0) * texel).rgb;
	vec3 J = texture(input_texture, norm_uv + vec2(-1.0, -1.0) * texel).rgb;
	vec3 K = texture(input_texture, norm_uv + vec2( 1.0, -1.0) * texel).rgb;
	vec3 L = texture(input_texture, norm_uv + vec2(-1.0,  1.0) * texel).rgb;
	vec3 M = texture(input_texture, norm_uv + vec2( 1.0,  1.0) * texel).rgb;

	vec3 result = E * 0.125;
	result += (A + C + G + I) * 0.03125;
	result += (B + D + F + H) * 0.0625;
	result += (J + K + L + M) * 0.125;

	imageStore(output_image, pos, vec4(result, 1.0));
}
