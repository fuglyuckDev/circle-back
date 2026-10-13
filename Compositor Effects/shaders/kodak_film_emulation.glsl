#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;

layout(push_constant, std430) uniform Params {
	float exposure_ev;
	float gamma;
	float filmic_shoulder;
	float saturation;
	float shadow_tint_weight;
	float highlight_tint_weight;
	float shadow_crush;
	float highlight_crush;
	vec4 lift;
	vec4 gain;
	vec4 shadow_tint;
	vec4 highlight_tint;
} params;

float luma(vec3 color) {
	return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

// Normalized photochemical film S-curve response function (f(0)=0, f(1)=1)
vec3 filmic_scurve(vec3 x, float shoulder) {
	float s = max(shoulder * 2.0, 0.001);
	// Soft shoulder compression with normalized white point
	vec3 num = x * (vec3(1.0) + x * s);
	vec3 den = x + vec3(s);
	vec3 unscaled = num / max(den, vec3(0.0001));
	float w_scale = (1.0 + s) / (1.0 + s); // Normalizes 1.0 to 1.0
	return unscaled;
}

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(output_image);
	if (pos.x >= size.x || pos.y >= size.y) {
		return;
	}

	vec2 uv = (vec2(pos) + vec2(0.5)) / vec2(size);
	vec3 base_color = texture(input_texture, uv).rgb;

	// Exposure EV adjustment
	vec3 col = base_color * pow(2.0, params.exposure_ev);

	// Lift / Gain balance
	col = max(col + (params.lift.rgb - vec3(0.5)) * 0.4, vec3(0.0));
	col = col * (params.gain.rgb * 2.0);
	col = pow(max(col, vec3(0.0)), vec3(1.0 / max(params.gamma, 0.1)));

	// Photochemical filmic shoulder curve
	if (params.filmic_shoulder > 0.001) {
		col = filmic_scurve(col, params.filmic_shoulder);
	}

	// Shadow/Highlight density crush
	col = max(col - vec3(params.shadow_crush * 0.03), vec3(0.0));
	col = min(col, vec3(1.0 / max(1.0 - params.highlight_crush * 0.2, 0.01)));

	// Photochemical dye layer crosstalk & tinting
	float lum = luma(col);
	float shadow_w = clamp(1.0 - lum * 2.0, 0.0, 1.0);
	float highlight_w = clamp(lum * 1.5 - 0.5, 0.0, 1.0);

	vec3 s_tint = col + (params.shadow_tint.rgb - vec3(0.5)) * params.shadow_tint_weight * 0.4;
	vec3 h_tint = col + (params.highlight_tint.rgb - vec3(0.5)) * params.highlight_tint_weight * 0.6;

	col = mix(col, s_tint, shadow_w);
	col = mix(col, h_tint, highlight_w);

	// Film grain dye coupling
	float post_lum = luma(col);
	vec3 final_color = mix(vec3(post_lum), col, params.saturation);

	imageStore(output_image, pos, vec4(clamp(final_color, 0.0, 1.0), 1.0));
}
