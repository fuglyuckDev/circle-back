#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;

layout(push_constant, std430) uniform Params {
	float brightness;
	float contrast;
	float saturation;
	float gamma;
	float exposure;
	float temperature;
	float tint;
	float hue_shift;
	float vibrance;
	float contrast_pivot;
	float lift;
	float gain;
	float shadow_lift;
	float midtone_adjust;
	float highlight_adjust;
	float shadow_threshold;
	float highlight_threshold;
	float gamma_r;
	float gamma_g;
	float gamma_b;
	float clamp_output;
	float pad0;
	float pad1;
	float pad2;
} params;

vec3 rgb_to_hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv_to_rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

float zone_weight_shadow(float l, float threshold) {
	return 1.0 - smoothstep(0.0, threshold, l);
}

float zone_weight_highlight(float l, float threshold) {
	return smoothstep(threshold, 1.0, l);
}

float zone_weight_midtone(float l, float s_thr, float h_thr) {
	return max(1.0 - zone_weight_shadow(l, s_thr) - zone_weight_highlight(l, h_thr), 0.0);
}

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(output_image);
	if (pos.x >= size.x || pos.y >= size.y) return;

	vec2 uv = (vec2(pos) + vec2(0.5)) / vec2(size);
	vec3 color = texture(input_texture, uv).rgb;

	color *= pow(2.0, params.exposure);

	color.r *= 1.0 + params.temperature * 0.3;
	color.b *= 1.0 - params.temperature * 0.3;
	color.g *= 1.0 + params.tint * 0.2;

	color += vec3(params.brightness);

	color = (color - params.contrast_pivot) * params.contrast + params.contrast_pivot;

	float l = luma(color);
	color = mix(vec3(l), color, params.saturation);

	float max_c = max(color.r, max(color.g, color.b));
	float sat_approx = (max_c > 0.0001) ? (max_c - min(color.r, min(color.g, color.b))) / max_c : 0.0;
	float vib_weight = (1.0 - sat_approx) * params.vibrance;
	l = luma(color);
	color = mix(vec3(l), color, 1.0 + vib_weight);

	if (params.hue_shift != 0.0) {
		vec3 hsv = rgb_to_hsv(color);
		hsv.x = fract(hsv.x + params.hue_shift / 360.0);
		color = hsv_to_rgb(hsv);
	}

	color += vec3(params.lift);
	color *= params.gain;

	l = luma(color);
	float ws = zone_weight_shadow(l, params.shadow_threshold);
	float wh = zone_weight_highlight(l, params.highlight_threshold);
	float wm = zone_weight_midtone(l, params.shadow_threshold, params.highlight_threshold);
	color += vec3(ws * params.shadow_lift + wm * params.midtone_adjust + wh * params.highlight_adjust);

	vec3 g = max(vec3(params.gamma_r, params.gamma_g, params.gamma_b) * params.gamma, vec3(0.01));
	color = pow(max(color, vec3(0.0)), 1.0 / g);

	if (params.clamp_output > 0.5) {
		color = clamp(color, vec3(0.0), vec3(1.0));
	}

	imageStore(output_image, pos, vec4(color, 1.0));
}
