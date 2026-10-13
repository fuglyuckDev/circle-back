#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D mask_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;

layout(push_constant, std430) uniform Params {
	float blur_px;
	float dir_x;
	float dir_y;
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
} params;

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(output_image);
	if (pos.x >= size.x || pos.y >= size.y) return;

	vec2 uv = (vec2(pos) + 0.5) / vec2(size);
	vec2 texel = (vec2(1.0) / vec2(size)) * (float(size.y) / 1080.0);

	// Directional binomial (Gaussian-approx) blur, 7 taps. Run it twice
	// (horizontal then vertical, ping-ponging textures) so the masks feather
	// isotropically instead of leaving a cross-shaped kernel behind.
	vec2 dir = vec2(params.dir_x, params.dir_y) * (params.blur_px * 0.5 * texel);

	vec4 acc = texture(mask_texture, uv) * 20.0; // weights 1-6-15-20-15-6-1
	float wsum = 20.0;
	for (int i = 1; i <= 3; i++) {
		float w = (i == 1) ? 15.0 : ((i == 2) ? 6.0 : 1.0);
		vec2 off = dir * float(i);
		acc += w * (texture(mask_texture, clamp(uv + off, vec2(0.0), vec2(1.0)))
		          + texture(mask_texture, clamp(uv - off, vec2(0.0), vec2(1.0))));
		wsum += 2.0 * w;
	}
	acc /= wsum;

	imageStore(output_image, pos, vec4(acc.rgb, 1.0));
}