#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;

layout(push_constant, std430) uniform Params {
	float distortion_k1;
	float distortion_scale;
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
	vec2 center_uv = (uv - vec2(0.5)) * params.distortion_scale;
	float r2 = dot(center_uv, center_uv);

	vec2 distorted_uv = vec2(0.5) + center_uv * (1.0 + params.distortion_k1 * r2);

	if (distorted_uv.x < 0.0 || distorted_uv.x > 1.0 || distorted_uv.y < 0.0 || distorted_uv.y > 1.0) {
		imageStore(output_image, pos, vec4(0.0, 0.0, 0.0, 1.0));
		return;
	}

	vec3 base_color = texture(input_texture, distorted_uv).rgb;
	imageStore(output_image, pos, vec4(clamp(base_color, 0.0, 1.0), 1.0));
}
