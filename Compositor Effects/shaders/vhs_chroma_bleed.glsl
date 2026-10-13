#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;

layout(push_constant, std430) uniform Params {
	float chroma_bleed;
	float tape_noise;
	float scanline_intensity;
	float head_switching;
	float time;
	float pad0;
	float pad1;
	float pad2;
} params;

vec3 rgb2yiq(vec3 c) {
	return vec3(
		dot(c, vec3(0.299, 0.587, 0.114)),
		dot(c, vec3(0.596, -0.274, -0.322)),
		dot(c, vec3(0.211, -0.523, 0.312))
	);
}

vec3 yiq2rgb(vec3 c) {
	return vec3(
		c.x + 0.956 * c.y + 0.621 * c.z,
		c.x - 0.272 * c.y - 0.647 * c.z,
		c.x - 1.106 * c.y + 1.703 * c.z
	);
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

	vec2 offset_uv = uv;
	if (uv.y > (1.0 - params.head_switching * 0.05)) {
		float jitter = (hash21(vec2(params.time * 0.1, pos.y)) - 0.5) * 0.02 * params.head_switching;
		offset_uv.x += jitter;
	}

	vec3 c_center = texture(input_texture, offset_uv).rgb;
	float y = rgb2yiq(c_center).x;

	vec2 chroma_uv = clamp(offset_uv - vec2(params.chroma_bleed * 8.0 * texel.x, 0.0), vec2(0.0), vec2(1.0));
	vec3 c_chroma = texture(input_texture, chroma_uv).rgb;
	vec2 iq = rgb2yiq(c_chroma).yz;

	vec3 rgb = yiq2rgb(vec3(y, iq));

	// Smooth Anti-Aliased Scanlines (No Nyquist Moiré Shimmer)
	float scanline = 0.5 + 0.5 * cos(uv.y * vec2(size).y * 3.14159);
	rgb *= mix(1.0, scanline, params.scanline_intensity * 0.25);

	float noise = (hash21(uv + vec2(params.time * 0.1)) - 0.5) * params.tape_noise * 0.15;
	rgb += vec3(noise);

	imageStore(output_image, pos, vec4(clamp(rgb, 0.0, 1.0), 1.0));
}
