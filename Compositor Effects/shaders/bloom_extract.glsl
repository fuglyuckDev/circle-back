#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;

layout(push_constant, std430) uniform Params {
	float threshold;
	float knee;
	float pad0;
	float pad1;
} params;

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(output_image);
	if (pos.x >= size.x || pos.y >= size.y) return;

	vec2 uv = (vec2(pos) + 0.5) / vec2(size);
	vec3 avg = texture(input_texture, uv).rgb;

	float l = luma(avg);
	float rq = clamp(l - params.threshold + params.knee, 0.0, params.knee * 2.0);
	float val = max(l - params.threshold, (rq * rq) / (4.0 * params.knee + 0.0001));
	avg = avg * (val / max(l, 0.0001));

	imageStore(output_image, pos, vec4(avg, 1.0));
}
