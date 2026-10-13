#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform readonly image2D input_image;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(input_image);
	if (pos.x >= size.x || pos.y >= size.y) {
		return;
	}
	vec4 col = imageLoad(input_image, pos);
	imageStore(output_image, pos, col);
}
