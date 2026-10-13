#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;

layout(push_constant, std430) uniform Params {
	float dither_amount;
	float color_depth;
	float dither_scale;
	float pad;
} params;

const float bayer_matrix[16] = float[16](
	0.0 / 16.0,  8.0 / 16.0,  2.0 / 16.0, 10.0 / 16.0,
	12.0 / 16.0, 4.0 / 16.0, 14.0 / 16.0,  6.0 / 16.0,
	3.0 / 16.0, 11.0 / 16.0,  1.0 / 16.0,  9.0 / 16.0,
	15.0 / 16.0, 7.0 / 16.0, 13.0 / 16.0,  5.0 / 16.0
);

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(output_image);
	if (pos.x >= size.x || pos.y >= size.y) {
		return;
	}

	vec2 uv = (vec2(pos) + vec2(0.5)) / vec2(size);
	vec3 base_color = texture(input_texture, uv).rgb;

	ivec2 pixel = ivec2(vec2(pos) / max(params.dither_scale, 1.0)) % 4;
	float bayer = bayer_matrix[pixel.y * 4 + pixel.x] - 0.5;

	vec3 dithered = base_color + vec3(bayer * params.dither_amount * 0.25);

	float levels = max(params.color_depth, 2.0);
	vec3 quantized = floor(dithered * (levels - 1.0) + 0.5) / (levels - 1.0);

	imageStore(output_image, pos, vec4(clamp(quantized, 0.0, 1.0), 1.0));
}
