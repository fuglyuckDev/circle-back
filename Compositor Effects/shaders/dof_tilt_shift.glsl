#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_texture;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D output_image;

layout(push_constant, std430) uniform Params {
	float focus_center;
	float focus_width;
	float blur_amount;
	float sigma;
	float saturation_boost;
	float angle;
	float shape;
	float highlight_boost;
	float highlight_threshold;
	float strength;
	float pad0;
	float pad1;
	float pad2;
	float pad3;
	float pad4;
	float pad5;
} params;

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

float karis_weight(vec3 c) {
	return 1.0 / (1.0 + luma(c));
}

float gaussian(float x, float s) {
	return exp(-(x * x) / (2.0 * s * s));
}

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = imageSize(output_image);
	if (pos.x >= size.x || pos.y >= size.y) return;

	vec2 uv = (vec2(pos) + 0.5) / vec2(size);
	vec2 texel = (vec2(1.0) / vec2(size)) * (float(size.y) / 1080.0);
	vec3 original = texture(input_texture, uv).rgb;

	float aspect = float(size.x) / float(size.y);
	vec2 aspect_uv = uv;
	aspect_uv.x = (aspect_uv.x - 0.5) * aspect + 0.5;

	float dist_from_focus;
	if (params.shape > 0.5) {
		dist_from_focus = distance(aspect_uv, vec2(0.5, params.focus_center));
	} else {
		float a = radians(params.angle);
		vec2 dir = vec2(cos(a), sin(a));
		vec2 center = vec2(0.5, params.focus_center);
		dist_from_focus = abs(dot(aspect_uv - center, dir));
	}

	float half_width = params.focus_width * 0.5;
	float blur_factor = smoothstep(half_width, half_width + 0.15, dist_from_focus);

	int radius = int(blur_factor * params.blur_amount);
	radius = clamp(radius, 0, 32);

	vec3 color = original;

	if (radius > 0) {
		float s = params.sigma > 0.001 ? params.sigma : float(radius) / 3.0;
		vec3 accum = vec3(0.0);
		float weight_sum = 0.0;

		for (int dy = -radius; dy <= radius; dy++) {
			for (int dx = -radius; dx <= radius; dx++) {
				float d = length(vec2(float(dx), float(dy)));
				if (d > float(radius) + 0.5) continue;

				vec2 offset = vec2(float(dx), float(dy)) * texel;
				vec3 sample_col = texture(input_texture, clamp(uv + offset, vec2(0.0), vec2(1.0))).rgb;

				if (params.highlight_boost > 0.0) {
					float l = luma(sample_col);
					if (l > params.highlight_threshold) {
						sample_col *= 1.0 + params.highlight_boost * (l - params.highlight_threshold);
					}
				}

				float w = gaussian(d, s) * karis_weight(sample_col);
				accum += sample_col * w;
				weight_sum += w;
			}
		}
		color = accum / max(weight_sum, 0.0001);
	}

	if (params.saturation_boost > 1.001) {
		float l = luma(color);
		color = mix(vec3(l), color, params.saturation_boost);
	}

	vec3 result = mix(original, color, params.strength);
	imageStore(output_image, pos, vec4(clamp(result, 0.0, 1.0), 1.0));
}
