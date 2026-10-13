#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;

layout(push_constant, std430) uniform Params {
	float vision_mode; // 0 = P43 Green, 1 = P45 White, 2 = Thermal FLIR Ironbow, 3 = Thermal FLIR Rainbow
	float light_gain;
	float sensor_noise;
	float phosphor_bloom;
	float scanline_darkness;
	float auto_gating_threshold;
	float vignette_intensity;
	float time;
	float animation_intensity;
	float pad0;
	float pad1;
	float pad2;
} params;

float luma(vec3 color) {
	return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

vec3 flir_ironbow(float t) {
	t = clamp(t, 0.0, 1.0);
	vec3 c0 = vec3(0.0, 0.0, 0.2);
	vec3 c1 = vec3(0.5, 0.0, 0.5);
	vec3 c2 = vec3(0.9, 0.2, 0.0);
	vec3 c3 = vec3(1.0, 0.8, 0.0);
	vec3 c4 = vec3(1.0, 1.0, 1.0);

	if (t < 0.25) return mix(c0, c1, t * 4.0);
	if (t < 0.50) return mix(c1, c2, (t - 0.25) * 4.0);
	if (t < 0.75) return mix(c2, c3, (t - 0.50) * 4.0);
	return mix(c3, c4, (t - 0.75) * 4.0);
}

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(output_image);
	if (pos.x >= size.x || pos.y >= size.y) {
		return;
	}

	vec2 uv = (vec2(pos) + vec2(0.5)) / vec2(size);
	vec2 aspect = vec2(float(size.x) / float(size.y), 1.0);
	vec3 base_color = texture(input_texture, uv).rgb;

	float lum = luma(base_color);

	// Light amplification gain
	lum *= params.light_gain;

	// Auto-gating bright light protection
	if (lum > params.auto_gating_threshold) {
		lum = params.auto_gating_threshold + (lum - params.auto_gating_threshold) * 0.15;
	}

	// Dynamic sensor noise & phosphor grain
	float noise = (hash21(uv + vec2(params.time * 0.1, params.time * 0.2)) - 0.5) * params.sensor_noise * params.animation_intensity;
	lum = max(lum + noise, 0.0);

	vec3 final_color = vec3(0.0);

	int m = int(params.vision_mode);
	if (m == 0) {
		// P43 Green Phosphor Night Vision
		final_color = vec3(lum * 0.15, lum * 1.1, lum * 0.25);
		final_color += vec3(0.0, max(lum - 0.7, 0.0) * params.phosphor_bloom * 1.5, 0.0);
	} else if (m == 1) {
		// P45 White Phosphor Night Vision
		final_color = vec3(lum * 0.85, lum * 0.95, lum * 1.1);
		final_color += vec3(max(lum - 0.7, 0.0) * params.phosphor_bloom);
	} else if (m == 2) {
		// Thermal FLIR Ironbow
		final_color = flir_ironbow(lum);
	} else {
		// Thermal FLIR Rainbow
		float t = clamp(lum, 0.0, 1.0);
		final_color = 0.5 + 0.5 * cos(6.28318 * (t + vec3(0.0, 0.33, 0.67)));
	}

	// Tube Scanlines
	float scanline = sin(uv.y * vec2(size).y * 3.14159) * 0.5 + 0.5;
	final_color *= mix(1.0, scanline, params.scanline_darkness * 0.35);

	// Optical tube vignetting
	float dist_sq = dot((uv - vec2(0.5)) * aspect, (uv - vec2(0.5)) * aspect);
	float vignette = clamp(1.0 - dist_sq * params.vignette_intensity * 2.5, 0.0, 1.0);
	final_color *= vignette;

	imageStore(output_image, pos, vec4(clamp(final_color, 0.0, 1.0), 1.0));
}
