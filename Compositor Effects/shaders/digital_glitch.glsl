#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;

layout(push_constant, std430) uniform Params {
	float glitch_intensity;
	float line_displacement;
	float chromatic_shift;
	float time;
	float animation_intensity;
	float pad0;
	float pad1;
	float pad2;
} params;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(output_image);
	if (pos.x >= size.x || pos.y >= size.y) {
		return;
	}

	vec2 uv = (vec2(pos) + vec2(0.5)) / vec2(size);
	vec2 texel = (vec2(1.0) / vec2(size)) * (float(size.y) / 1080.0);

	float slice_y = floor(uv.y * 32.0);
	float slice_noise = hash21(vec2(slice_y, floor(params.time * 12.0)));

	vec2 g_uv = uv;
	if (slice_noise < params.glitch_intensity * 0.35) {
		float offset_x = (hash11(slice_y + params.time) - 0.5) * params.line_displacement * 0.1 * params.animation_intensity;
		g_uv.x = clamp(g_uv.x + offset_x, 0.0, 1.0);
	}

	float c_shift = params.chromatic_shift * params.glitch_intensity * 0.02;
	float r = texture(input_texture, clamp(g_uv + vec2(c_shift, 0.0), vec2(0.0), vec2(1.0))).r;
	float g = texture(input_texture, g_uv).g;
	float b = texture(input_texture, clamp(g_uv - vec2(c_shift, 0.0), vec2(0.0), vec2(1.0))).b;

	imageStore(output_image, pos, vec4(r, g, b, 1.0));
}
