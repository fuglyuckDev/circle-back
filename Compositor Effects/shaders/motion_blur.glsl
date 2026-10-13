#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;
layout(set = 0, binding = 2) uniform sampler2D velocity_texture;

layout(push_constant, std430) uniform Params {
	float strength;
	float velocity_scale;
	float sample_count;
	float min_speed;
	float max_blur;
	float debug_mode;
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
} params;

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

vec3 hue2rgb(float h) {
	vec3 p = abs(fract(vec3(h, h, h) + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return clamp(p - 1.0, 0.0, 1.0);
}

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(output_image);
	if (pos.x >= size.x || pos.y >= size.y) return;

	vec2 size_f = vec2(size);
	vec2 uv = (vec2(pos) + 0.5) / size_f;
	vec2 texel = (vec2(1.0) / size_f) * (float(size.y) / 1080.0);
	vec3 base = texture(input_texture, uv).rgb;

	// Godot stores motion vectors in NDC-ish space; velocity_scale converts to
	// a pixel offset (0.5 = NDC -> screen fraction, then * size -> pixels).
	vec2 vel = texture(velocity_texture, uv).xy;
	vec2 motion_px = vel * params.velocity_scale * size_f;
	float speed_px = length(motion_px);

	// Debug: velocity speed (heat) / direction (hue).
	if (params.debug_mode > 0.5 && params.debug_mode < 1.5) {
		float t = clamp(speed_px / 30.0, 0.0, 1.0);
		imageStore(output_image, pos, vec4(mix(vec3(0.0, 0.0, 0.1), vec3(1.0, 0.9, 0.2), t), 1.0));
		return;
	}
	if (params.debug_mode > 1.5 && params.debug_mode < 2.5) {
		vec2 d = speed_px > 0.5 ? motion_px / max(speed_px, 1.0) : vec2(0.0);
		float ang = atan(d.y, d.x) / 6.28318530718 + 0.5;
		imageStore(output_image, pos, vec4(hue2rgb(ang), 1.0));
		return;
	}

	if (speed_px < params.min_speed) {
		imageStore(output_image, pos, vec4(base, 1.0));
		return;
	}

	float blur_len = clamp(speed_px * params.strength, params.min_speed, params.max_blur);
	vec2 dir = motion_px / max(speed_px, 1e-4);
	int n = int(clamp(params.sample_count, 4.0, 32.0));

	// Directional gather along the motion line. Center-weighted so a small blur
	// reads as motion smear rather than a hard double image.
	vec3 acc = base;
	float wsum = 1.0;
	for (int i = 0; i < 32; i++) {
		if (i >= n) break;
		float t = (float(i) / float(n - 1)) * 2.0 - 1.0;
		vec2 p = clamp(uv + dir * (t * blur_len * texel), vec2(0.0), vec2(1.0));
		vec3 c = texture(input_texture, p).rgb;
		float w = 1.0 - abs(t) * 0.6;
		acc += c * w;
		wsum += w;
	}
	vec3 blurred = acc / max(wsum, 0.0001);

	vec3 result = mix(base, blurred, clamp(blur_len / max(params.max_blur, 0.001), 0.0, 1.0));
	imageStore(output_image, pos, vec4(clamp(result, 0.0, 1.0), 1.0));
}