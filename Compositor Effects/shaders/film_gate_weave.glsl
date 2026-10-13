#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;

layout(push_constant, std430) uniform Params {
	float weave_amount;
	float weave_speed;
	float time;
	float pad0;
} params;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(output_image);
	if (pos.x >= size.x || pos.y >= size.y) {
		return;
	}

	vec2 uv = (vec2(pos) + vec2(0.5)) / vec2(size);
	vec2 texel = vec2(1.0) / vec2(size);

	float frame = floor(params.time * 24.0 * params.weave_speed);
	float jitter_x = (hash11(frame * 12.3) - 0.5) * params.weave_amount * 4.0 * texel.x;
	float jitter_y = (hash11(frame * 45.6) - 0.5) * params.weave_amount * 2.0 * texel.y;

	vec2 offset_uv = clamp(uv + vec2(jitter_x, jitter_y), vec2(0.0), vec2(1.0));
	vec3 base_color = texture(input_texture, offset_uv).rgb;

	imageStore(output_image, pos, vec4(base_color, 1.0));
}
