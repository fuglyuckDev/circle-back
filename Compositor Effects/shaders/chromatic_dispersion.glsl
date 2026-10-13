#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;

layout(push_constant, std430) uniform Params {
	float aberration_amount;
	float radial_exponent;
	float pad0;
	float pad1;
} params;

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(output_image);
	if (pos.x >= size.x || pos.y >= size.y) {
		return;
	}

	vec2 uv = (vec2(pos) + vec2(0.5)) / vec2(size);
	vec2 texel = (vec2(1.0) / vec2(size)) * (float(size.y) / 1080.0);

	vec2 dist_from_center = uv - vec2(0.5);
	float dist_sq = dot(dist_from_center, dist_from_center);

	float falloff = pow(dist_sq, params.radial_exponent * 0.5);
	vec2 offset = dist_from_center * falloff * params.aberration_amount * 0.05;

	vec2 uv_r = clamp(uv + offset, vec2(0.0), vec2(1.0));
	vec2 uv_g = uv;
	vec2 uv_b = clamp(uv - offset, vec2(0.0), vec2(1.0));

	float r = texture(input_texture, uv_r).r;
	float g = texture(input_texture, uv_g).g;
	float b = texture(input_texture, uv_b).b;

	imageStore(output_image, pos, vec4(r, g, b, 1.0));
}
