#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform restrict image2D output_image;

layout(push_constant, std430) uniform Params {
	vec2 inv_tex_size;
	float filter_radius;
	float pad0;
} params;

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(output_image);
	if (pos.x >= size.x || pos.y >= size.y) return;

	vec2 norm_uv = (vec2(pos) + 0.5) / vec2(size);
	vec2 texel = params.inv_tex_size * params.filter_radius;

	vec3 A = texture(input_texture, norm_uv + vec2(-1.0, -1.0) * texel).rgb;
	vec3 B = texture(input_texture, norm_uv + vec2( 0.0, -1.0) * texel).rgb;
	vec3 C = texture(input_texture, norm_uv + vec2( 1.0, -1.0) * texel).rgb;
	vec3 D = texture(input_texture, norm_uv + vec2(-1.0,  0.0) * texel).rgb;
	vec3 E = texture(input_texture, norm_uv + vec2( 0.0,  0.0) * texel).rgb;
	vec3 F = texture(input_texture, norm_uv + vec2( 1.0,  0.0) * texel).rgb;
	vec3 G = texture(input_texture, norm_uv + vec2(-1.0,  1.0) * texel).rgb;
	vec3 H = texture(input_texture, norm_uv + vec2( 0.0,  1.0) * texel).rgb;
	vec3 I = texture(input_texture, norm_uv + vec2( 1.0,  1.0) * texel).rgb;

	// 9-tap tent filter (3x3 bilinear weights)
	vec3 upsampled = E * 0.25;
	upsampled += (B + D + F + H) * 0.125;
	upsampled += (A + C + G + I) * 0.0625;

	// Additive accumulation: blend upsampled bloom into existing mip content
	vec3 existing = imageLoad(output_image, pos).rgb;
	imageStore(output_image, pos, vec4(existing + upsampled, 1.0));
}
